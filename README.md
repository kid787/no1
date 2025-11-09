# トレードジャーナル自動化システム

n8nを使用したトレード記録・分析・レポート自動化システム

## 概要

このプロジェクトは、トレード実行から記録、分析、レポート送信までを自動化するn8nワークフローです。

### 機能

- 📊 **トレード実行記録** - Webhook経由で自動記録
- 📅 **Google Calendar連携** - カレンダービューで視覚的に管理
- 📈 **Google Sheets連携** - データベースとして詳細記録・分析
- 📝 **Notion連携** - リッチなジャーナルとメモ管理
- 🧮 **統計計算** - 勝率、損益率、リスクリワード等を自動計算
- 📧 **レポート送信** - 日次/週次/月次レポートを自動送信

## ワークフロー

```
トレード実行
  → Webhook受信
  → データ検証・整形
  → Google Calendar登録
  → Google Sheets記録
  → Notion更新
  → 統計計算
  → レポート送信（Email/Slack）
```

## ディレクトリ構造

```
no1/
├── README.md                           # このファイル
├── docs/
│   ├── SETUP.md                        # セットアップガイド
│   └── USAGE.md                        # 使い方ガイド
├── workflows/
│   ├── trade-journal-main.json         # メインワークフロー
│   └── daily-report.json               # 日次レポートワークフロー
├── templates/
│   ├── google-sheets-template.md       # Google Sheetsテンプレート
│   └── notion-database-template.md     # Notionデータベーステンプレート
└── examples/
    └── sample-webhook-payload.json     # サンプルWebhookデータ
```

## クイックスタート

1. [セットアップガイド](docs/SETUP.md)を参照してn8nと各種サービスを設定
2. `workflows/trade-journal-main.json`をn8nにインポート
3. 各ノードの認証情報を設定
4. Webhookエンドポイントにトレードデータを送信

詳細は[使い方ガイド](docs/USAGE.md)を参照してください。

## 必要なもの

- n8n（セルフホストまたはn8n Cloud）
- Googleアカウント（Calendar、Sheets用）
- Notionアカウント
- メール送信サービス（Gmail等）またはSlack（オプション）

## サポートされるトレード情報

- 日時
- 通貨ペア/銘柄
- エントリー価格
- エグジット価格
- ロット数/数量
- 損益（金額・pips）
- トレード方向（買い/売り）
- ストップロス/テイクプロフィット
- メモ・反省点
- チャート画像URL（オプション）

## ライセンス

MIT

## 貢献

Issue、Pull Requestは大歓迎です！
