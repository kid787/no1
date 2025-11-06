# トレーディングジャーナル

トレードの記録と感情を管理するWebアプリケーション

## 概要

このアプリケーションは、トレーダーが自分のトレード記録と感情を記録・管理し、振り返りを通じて成長できるように設計されています。

## 機能

### 📊 ダッシュボード
- 総トレード数
- 総損益
- 勝率の表示

### 💼 トレード記録
- トレードの登録・編集・削除
- 日付、銘柄/通貨ペア、売買区分
- エントリー価格、決済価格、数量
- 損益の自動計算
- ステータス管理（オープン/クローズ）

### 📝 トレード日記
- 感情と考えの記録
- エントリータイプ（トレード前/中/後、一般）
- 自由形式のメモ
- タイムスタンプ付き

## 技術スタック

### バックエンド
- Node.js + Express
- TypeScript
- SQLite（better-sqlite3）

### フロントエンド
- React 18
- TypeScript
- Vite
- Tailwind CSS
- React Router

## セットアップ

### 必要な環境
- Node.js 18以上
- npm または yarn

### インストール

1. リポジトリのクローン
```bash
git clone <repository-url>
cd no1
```

2. バックエンドのセットアップ
```bash
cd backend
npm install
npm run dev
```
バックエンドは http://localhost:3001 で起動します

3. フロントエンドのセットアップ（別のターミナルで）
```bash
cd frontend
npm install
npm run dev
```
フロントエンドは http://localhost:3000 で起動します

## 開発

### バックエンド開発サーバー
```bash
cd backend
npm run dev
```

### フロントエンド開発サーバー
```bash
cd frontend
npm run dev
```

### ビルド

#### バックエンド
```bash
cd backend
npm run build
npm start
```

#### フロントエンド
```bash
cd frontend
npm run build
npm run preview
```

## API エンドポイント

### Trades
- `GET /api/trades` - 全トレード取得
- `GET /api/trades/stats` - トレード統計取得
- `GET /api/trades/:id` - 特定のトレード取得
- `POST /api/trades` - トレード作成
- `PUT /api/trades/:id` - トレード更新
- `DELETE /api/trades/:id` - トレード削除

### Journal
- `GET /api/journal` - 全ジャーナルエントリー取得
- `GET /api/journal/:id` - 特定のエントリー取得
- `GET /api/journal/trade/:tradeId` - トレード別エントリー取得
- `POST /api/journal` - エントリー作成
- `PUT /api/journal/:id` - エントリー更新
- `DELETE /api/journal/:id` - エントリー削除

## プロジェクト構造

```
no1/
├── backend/
│   ├── src/
│   │   ├── database/
│   │   │   └── db.ts          # データベース初期化
│   │   ├── models/
│   │   │   ├── Trade.ts       # トレードモデル
│   │   │   └── JournalEntry.ts # ジャーナルモデル
│   │   ├── routes/
│   │   │   ├── trades.ts      # トレードルート
│   │   │   └── journal.ts     # ジャーナルルート
│   │   └── index.ts           # エントリーポイント
│   ├── package.json
│   └── tsconfig.json
├── frontend/
│   ├── src/
│   │   ├── components/
│   │   │   ├── TradeForm.tsx
│   │   │   └── JournalForm.tsx
│   │   ├── pages/
│   │   │   ├── Dashboard.tsx
│   │   │   ├── Trades.tsx
│   │   │   └── Journal.tsx
│   │   ├── services/
│   │   │   └── api.ts         # APIクライアント
│   │   ├── types/
│   │   │   └── index.ts       # 型定義
│   │   ├── App.tsx
│   │   ├── main.tsx
│   │   └── index.css
│   ├── package.json
│   └── vite.config.ts
└── README.md
```

## データベーススキーマ

### trades テーブル
- id: INTEGER PRIMARY KEY
- date: TEXT
- symbol: TEXT
- side: TEXT ('buy' | 'sell')
- entry_price: REAL
- exit_price: REAL
- quantity: REAL
- profit_loss: REAL
- status: TEXT ('open' | 'closed')
- created_at: TEXT

### journal_entries テーブル
- id: INTEGER PRIMARY KEY
- trade_id: INTEGER (FOREIGN KEY)
- entry_type: TEXT ('before' | 'during' | 'after' | 'general')
- emotion: TEXT
- content: TEXT
- created_at: TEXT

## ライセンス

ISC
