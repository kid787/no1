# セットアップガイド

このガイドでは、トレードジャーナル自動化システムをゼロからセットアップする手順を説明します。

## 目次

1. [前提条件](#前提条件)
2. [n8nのセットアップ](#n8nのセットアップ)
3. [Google Calendar設定](#google-calendar設定)
4. [Google Sheets設定](#google-sheets設定)
5. [Notion設定](#notion設定)
6. [n8nワークフローのインポート](#n8nワークフローのインポート)
7. [認証情報の設定](#認証情報の設定)
8. [ワークフローのテスト](#ワークフローのテスト)
9. [トラブルシューティング](#トラブルシューティング)

---

## 前提条件

以下のアカウントとサービスが必要です：

- [ ] Googleアカウント
- [ ] Notionアカウント（無料プランでOK）
- [ ] n8nアカウント（n8n Cloudまたはセルフホスト）
- [ ] メール送信用のGmailアカウント

### 推奨環境

- **n8n Cloud**: 最も簡単。月額$20から
- **セルフホスト**: 無料だが、VPSやDockerの知識が必要

---

## n8nのセットアップ

### オプション1: n8n Cloud（推奨）

1. https://n8n.io にアクセス
2. 「Start free trial」または「Sign up」をクリック
3. アカウントを作成してログイン
4. 新しいワークフローを作成する準備完了

### オプション2: セルフホスト（Docker）

```bash
# Docker Composeを使用
docker run -it --rm \
  --name n8n \
  -p 5678:5678 \
  -v ~/.n8n:/home/node/.n8n \
  n8nio/n8n
```

ブラウザで http://localhost:5678 にアクセス

詳細: https://docs.n8n.io/hosting/installation/docker/

---

## Google Calendar設定

### 1. カレンダーの作成

1. Google Calendarにアクセス
2. 左サイドバーの「+」→「新しいカレンダーを作成」
3. 名前: 「Trade Journal」
4. タイムゾーン: Asia/Tokyo
5. 「カレンダーを作成」をクリック

### 2. OAuth認証情報の作成（n8nで使用）

n8nでGoogle Calendarノードを使用する際に、自動的にOAuth認証が行われます。
特別な設定は不要ですが、初回接続時にGoogleアカウントでの認証が必要です。

**手順**:
1. n8nのGoogle Calendarノードを追加
2. 「Create New Credential」をクリック
3. Googleアカウントでログイン
4. カレンダーへのアクセスを許可

---

## Google Sheets設定

### 1. スプレッドシートの作成

1. Google Sheetsにアクセス
2. 「空白」から新しいスプレッドシートを作成
3. 名前: 「Trade Journal」

### 2. ヘッダー行の設定

`templates/google-sheets-template.md` に詳細な設定方法があります。

**簡易版**:
1行目に以下を入力：

```
日時 | 通貨ペア | 方向 | エントリー | エグジット | ロット | 損益額 | 通貨 | Pips | 結果 | メモ | 感情 | タグ | チャート
```

### 3. スプレッドシートIDの取得

URLから以下の部分をコピー：
```
https://docs.google.com/spreadsheets/d/【ここをコピー】/edit
```

例: `1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms`

このIDを後で使用します。

---

## Notion設定

### 1. データベースの作成

`templates/notion-database-template.md` に詳細な設定方法があります。

**簡易版**:
1. Notionで新しいページを作成
2. `/database` → 「Table - Inline」を選択
3. タイトル: 「Trade Journal」

### 2. プロパティの追加

最低限必要なプロパティ：

| プロパティ名 | タイプ |
|-------------|--------|
| タイトル | Title |
| 日時 | Date |
| 通貨ペア | Select |
| 方向 | Select (買い, 売り) |
| エントリー | Number |
| エグジット | Number |
| 損益 | Number |
| 結果 | Select (勝ち, 負け) |
| タグ | Multi-select |

### 3. Notion Integration の作成

1. https://www.notion.so/my-integrations にアクセス
2. 「+ New integration」をクリック
3. 名前: 「Trade Journal n8n」
4. ワークスペースを選択
5. 「Submit」をクリック
6. **Internal Integration Token** をコピーして保存

### 4. データベースに統合を接続

1. Trade Journalデータベースページを開く
2. 右上の「⋮」→「Connections」→「Connect to」
3. 「Trade Journal n8n」を選択

### 5. データベースIDの取得

URLから32文字のIDを取得：
```
https://www.notion.so/【32文字のID】?v=...
```

---

## n8nワークフローのインポート

### 1. メインワークフローのインポート

1. n8nにログイン
2. 「Workflows」→「Add workflow」
3. 右上の「⋮」→「Import from File」
4. `workflows/trade-journal-main.json` を選択
5. ワークフロー名を確認

### 2. 日次レポートワークフローのインポート

同様に `workflows/daily-report.json` もインポート

---

## 認証情報の設定

### 1. Google Calendar認証

1. 「Google Calendar - Create Event」ノードをクリック
2. 「Credential to connect with」→「Create New」
3. Googleアカウントでログイン
4. カレンダーへのアクセスを許可
5. カレンダー選択: 「Trade Journal」または「primary」

### 2. Google Sheets認証

1. 「Google Sheets - Append Row」ノードをクリック
2. 「Credential to connect with」→「Create New」
3. Googleアカウントでログイン
4. Sheetsへのアクセスを許可
5. **Document ID**: 先ほど取得したスプレッドシートIDを入力
6. **Sheet Name**: 「Sheet1」または「gid=0」

「Get All Trades」ノードも同様に設定

### 3. Notion認証

1. 「Notion - Create Page」ノードをクリック
2. 「Credential to connect with」→「Create New」
3. **Authentication**: 「API Key」を選択
4. **API Key**: 先ほど取得したIntegration Tokenを入力
5. 「Save」をクリック
6. **Database ID**: 先ほど取得したNotionデータベースIDを入力

### 4. Gmail認証（レポート送信用）

1. 「Send Email Report」ノードをクリック
2. 「Credential to connect with」→「Create New」
3. Gmailアカウントでログイン
4. メール送信の許可
5. **From Email**: 送信元メールアドレス
6. **To Email**: 受信先メールアドレス（自分のメールでOK）

---

## ワークフローのテスト

### 1. Webhookエンドポイントの確認

1. 「Webhook - Trade Entry」ノードをクリック
2. 「Webhook URLs」の「Test URL」をコピー

例: `https://your-n8n.app/webhook-test/trade-entry`

### 2. サンプルデータでテスト

#### cURLを使用

```bash
curl -X POST https://your-n8n.app/webhook-test/trade-entry \
  -H "Content-Type: application/json" \
  -d @examples/sample-webhook-payload.json
```

#### Postmanを使用

1. 新しいリクエストを作成
2. Method: POST
3. URL: WebhookのTest URL
4. Body → raw → JSON
5. `examples/sample-webhook-payload.json` の内容をコピペ
6. 「Send」をクリック

### 3. 結果の確認

以下を確認してください：

- [ ] Google Calendarにイベントが作成された
- [ ] Google Sheetsに行が追加された
- [ ] Notionにページが作成された
- [ ] メールでレポートが届いた
- [ ] Webhook ResponseがJSONで返ってきた

---

## 本番運用への切り替え

### 1. Production URLの使用

1. ワークフローを「Active」にする
2. 「Webhook - Trade Entry」ノードで「Production URL」を使用
3. このURLをトレードアプリケーションやスクリプトに設定

### 2. 日次レポートの有効化

1. 「Daily Trade Report」ワークフローを開く
2. 右上の「Active」トグルをONにする
3. 毎日20:00（デフォルト）にレポートが自動送信される

時間を変更する場合：
1. 「Schedule - Every Day 20:00」ノードをクリック
2. Cron Expression を変更
   - 毎日21:00: `0 21 * * *`
   - 毎日朝8:00: `0 8 * * *`

---

## トラブルシューティング

### エラー: "Authentication failed"

**原因**: OAuth認証が切れた、または正しく設定されていない

**解決策**:
1. 該当ノードの認証情報を再設定
2. Googleアカウントで再度ログイン
3. 必要な権限をすべて許可

### エラー: "Sheet not found"

**原因**: スプレッドシートIDまたはシート名が間違っている

**解決策**:
1. スプレッドシートのURLを再確認
2. シート名を「Sheet1」または「gid=0」に変更
3. スプレッドシートが削除されていないか確認

### エラー: "Database not found" (Notion)

**原因**: データベースIDが間違っている、または統合が接続されていない

**解決策**:
1. NotionのデータベースURLを再確認
2. データベースに統合「Trade Journal n8n」を接続したか確認
3. Integration Tokenが正しいか確認

### Webhookが反応しない

**原因**: ワークフローがActiveになっていない

**解決策**:
1. ワークフロー右上の「Active」トグルをONにする
2. Production URLを使用しているか確認
3. URLのスペルミスがないか確認

### メールが届かない

**原因**: Gmail認証が切れた、またはスパムフォルダに入っている

**解決策**:
1. スパムフォルダを確認
2. Gmail認証情報を再設定
3. 「安全性の低いアプリのアクセス」を許可（必要な場合）

### データ形式エラー

**原因**: Webhookで送信するJSONの形式が間違っている

**解決策**:
1. `examples/sample-webhook-payload.json` と比較
2. 必須フィールドが含まれているか確認
3. データ型が正しいか確認（数値は数値、文字列は文字列）

---

## 次のステップ

セットアップが完了したら、以下を確認してください：

1. [使い方ガイド](USAGE.md) でWebhook送信方法を学ぶ
2. 実際のトレードで使用してみる
3. カスタマイズ（通貨ペア追加、統計項目追加など）

---

## サポート

問題が解決しない場合：

1. n8nのログを確認（各ノードの実行結果）
2. GitHubのIssueを作成
3. n8n公式ドキュメント: https://docs.n8n.io

---

おめでとうございます！セットアップが完了しました。
