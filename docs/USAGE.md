# 使い方ガイド

トレードジャーナル自動化システムの日常的な使い方を説明します。

## 目次

1. [基本的な使い方](#基本的な使い方)
2. [手動でトレードを記録](#手動でトレードを記録)
3. [自動化での記録](#自動化での記録)
4. [データの確認方法](#データの確認方法)
5. [レポートの見方](#レポートの見方)
6. [カスタマイズ](#カスタマイズ)
7. [Tips & ベストプラクティス](#tips--ベストプラクティス)

---

## 基本的な使い方

### ワークフローの全体像

```
1. トレード実行
   ↓
2. WebhookにPOSTリクエスト送信
   ↓
3. 自動的に以下が実行される：
   - Google Calendarにイベント作成
   - Google Sheetsにデータ追加
   - Notionにページ作成
   - 統計計算
   - レポート送信（Email）
```

---

## 手動でトレードを記録

### 方法1: cURLコマンド

ターミナルで以下を実行：

```bash
curl -X POST https://your-n8n-url/webhook/trade-entry \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2025-11-09T15:30:00+09:00",
    "symbol": "USD/JPY",
    "direction": "買い",
    "entryPrice": 149.50,
    "exitPrice": 149.85,
    "lotSize": 1.0,
    "stopLoss": 149.20,
    "takeProfit": 150.00,
    "profitLoss": {
      "amount": 3500,
      "currency": "JPY",
      "pips": 35
    },
    "notes": "上昇トレンド継続中。レジスタンスブレイクでエントリー。",
    "emotion": "冷静",
    "chartImageUrl": "",
    "tags": ["デイトレード", "トレンドフォロー", "成功"]
  }'
```

### 方法2: Postman / Insomnia

1. 新しいリクエストを作成
2. **Method**: POST
3. **URL**: `https://your-n8n-url/webhook/trade-entry`
4. **Headers**: `Content-Type: application/json`
5. **Body**: `examples/sample-webhook-payload.json` の内容
6. **Send**をクリック

### 方法3: Pythonスクリプト

```python
import requests
from datetime import datetime

def record_trade(symbol, direction, entry, exit, lot_size, profit, notes=""):
    url = "https://your-n8n-url/webhook/trade-entry"

    # Pips計算（簡易版）
    pips = (exit - entry) * 100 if "JPY" in symbol else (exit - entry) * 10000
    if direction == "売り":
        pips = -pips

    payload = {
        "timestamp": datetime.now().isoformat(),
        "symbol": symbol,
        "direction": direction,
        "entryPrice": entry,
        "exitPrice": exit,
        "lotSize": lot_size,
        "profitLoss": {
            "amount": profit,
            "currency": "JPY",
            "pips": round(pips, 1)
        },
        "notes": notes,
        "emotion": "普通",
        "tags": ["デイトレード"]
    }

    response = requests.post(url, json=payload)
    print(f"Status: {response.status_code}")
    print(f"Response: {response.json()}")

# 使用例
record_trade(
    symbol="USD/JPY",
    direction="買い",
    entry=149.50,
    exit=149.85,
    lot_size=1.0,
    profit=3500,
    notes="トレンドフォロー成功"
)
```

### 方法4: Google Apps Script（自動化）

Google Sheetsに手動入力したら自動的にn8nに送信：

```javascript
function onEdit(e) {
  const sheet = e.source.getActiveSheet();
  const row = e.range.getRow();

  // ヘッダー行をスキップ
  if (row === 1) return;

  const data = sheet.getRange(row, 1, 1, 14).getValues()[0];

  const payload = {
    timestamp: data[0],
    symbol: data[1],
    direction: data[2],
    entryPrice: data[3],
    exitPrice: data[4],
    lotSize: data[5],
    profitLoss: {
      amount: data[6],
      currency: data[7],
      pips: data[8]
    },
    notes: data[10],
    emotion: data[11],
    tags: data[12] ? data[12].split(", ") : []
  };

  const url = "https://your-n8n-url/webhook/trade-entry";

  UrlFetchApp.fetch(url, {
    method: "post",
    contentType: "application/json",
    payload: JSON.stringify(payload)
  });
}
```

---

## 自動化での記録

### TradingViewアラート連携

TradingViewのアラートからWebhookを送信：

1. TradingViewでアラートを作成
2. 「Webhook URL」に n8n の Webhook URL を入力
3. 「Message」に以下のJSON形式で入力：

```json
{
  "timestamp": "{{timenow}}",
  "symbol": "{{ticker}}",
  "direction": "買い",
  "entryPrice": {{close}},
  "exitPrice": {{close}},
  "lotSize": 1.0,
  "profitLoss": {
    "amount": 0,
    "currency": "USD",
    "pips": 0
  },
  "notes": "TradingViewアラートから自動記録",
  "tags": ["自動売買", "アラート"]
}
```

### MetaTrader 4/5 (MQL)

MT4/MT5のEAから直接送信：

```mql4
#include <JSON.mqh>

void SendTradeToWebhook(string symbol, string direction, double entry, double exit, double lots, double profit) {
   string url = "https://your-n8n-url/webhook/trade-entry";
   string headers = "Content-Type: application/json\r\n";

   CJAVal json;
   json["timestamp"] = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   json["symbol"] = symbol;
   json["direction"] = direction;
   json["entryPrice"] = entry;
   json["exitPrice"] = exit;
   json["lotSize"] = lots;
   json["profitLoss"]["amount"] = profit;
   json["profitLoss"]["currency"] = "USD";
   json["profitLoss"]["pips"] = (exit - entry) * 10000;
   json["notes"] = "MT4から自動送信";
   json["tags"][0] = "EA";

   string jsonStr = json.Serialize();

   char post[];
   char result[];
   StringToCharArray(jsonStr, post, 0, StringLen(jsonStr));

   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, post, result, headers);

   if(res == -1) {
      Print("Error: ", GetLastError());
   } else {
      Print("Trade recorded successfully");
   }
}
```

### Python自動売買スクリプト

```python
import requests
from datetime import datetime

class TradeJournal:
    def __init__(self, webhook_url):
        self.webhook_url = webhook_url

    def record(self, trade_data):
        """トレードをジャーナルに記録"""
        payload = {
            "timestamp": datetime.now().isoformat(),
            "symbol": trade_data.get("symbol"),
            "direction": trade_data.get("direction"),
            "entryPrice": trade_data.get("entry"),
            "exitPrice": trade_data.get("exit"),
            "lotSize": trade_data.get("lot_size", 1.0),
            "profitLoss": {
                "amount": trade_data.get("profit"),
                "currency": trade_data.get("currency", "USD"),
                "pips": self.calculate_pips(trade_data)
            },
            "notes": trade_data.get("notes", ""),
            "emotion": trade_data.get("emotion", "普通"),
            "tags": trade_data.get("tags", [])
        }

        try:
            response = requests.post(self.webhook_url, json=payload, timeout=10)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"Failed to record trade: {e}")
            return None

    def calculate_pips(self, trade_data):
        """Pipsを計算"""
        entry = trade_data.get("entry")
        exit = trade_data.get("exit")
        symbol = trade_data.get("symbol")
        direction = trade_data.get("direction")

        if "JPY" in symbol:
            pips = (exit - entry) * 100
        else:
            pips = (exit - entry) * 10000

        if direction == "売り":
            pips = -pips

        return round(pips, 1)

# 使用例
journal = TradeJournal("https://your-n8n-url/webhook/trade-entry")

# トレード記録
journal.record({
    "symbol": "EUR/USD",
    "direction": "買い",
    "entry": 1.0850,
    "exit": 1.0880,
    "lot_size": 0.5,
    "profit": 150,
    "currency": "USD",
    "notes": "欧州時間、サポートラインからの反発",
    "emotion": "冷静",
    "tags": ["デイトレード", "サポート反発"]
})
```

---

## データの確認方法

### Google Calendar

1. Google Calendarを開く
2. 「Trade Journal」カレンダーを選択
3. 月表示・週表示・日表示で確認
4. イベントをクリックして詳細を確認

**便利な機能**:
- 勝ちトレードは緑色
- 負けトレードは赤色
- カレンダービューで視覚的にトレード頻度を把握

### Google Sheets

1. Google Sheetsを開く
2. すべてのトレードデータを表形式で確認
3. フィルター機能で特定期間や通貨ペアを抽出
4. ピボットテーブルで統計分析

**便利な操作**:
```
# 特定通貨ペアのみ表示
データ → フィルタを作成 → 通貨ペア列で選択

# 損益でソート
損益額の列ヘッダーをクリック → 降順/昇順

# 月別の集計
挿入 → ピボットテーブル
```

### Notion

1. Notionを開く
2. 「Trade Journal」データベースを開く
3. 各ビューで確認：
   - **テーブルビュー**: すべてのデータ
   - **カレンダービュー**: 日付ベースで表示
   - **ボードビュー**: 通貨ペア別に整理
   - **タイムラインビュー**: 時系列で確認

**便利なフィルター**:
```
# 今週のトレードのみ
日時 is within → This week

# 勝ちトレードのみ
結果 = 勝ち

# 特定タグ
タグ contains デイトレード
```

---

## レポートの見方

### 即時レポート（トレード記録時）

トレード記録後、すぐにメールで以下の情報が届きます：

- 全体統計（総トレード数、勝率、総損益）
- パフォーマンス指標（平均勝ち/負け、プロフィットファクター）
- 本日の成績

### 日次レポート（毎日20:00）

毎日20:00に自動送信されるレポート：

- 本日の成績（トレード数、勝率、損益）
- 今週の成績
- 今月の成績
- 通貨ペア別トップ5

### レポートの活用方法

1. **日次レビュー**: 毎日のレポートで振り返り
2. **週次レビュー**: 週末に1週間の傾向を分析
3. **月次レビュー**: 月末に全体的なパフォーマンスを評価

---

## カスタマイズ

### 1. 通貨ペアの追加

Notionのデータベースで「通貨ペア」プロパティを編集：

1. プロパティをクリック
2. 「Edit property」
3. 新しいオプションを追加（例: BTC/USD, ETH/USD）

### 2. 感情タグの追加

同様に「感情」プロパティを編集して、自分に合ったタグを追加

### 3. レポート送信時間の変更

`workflows/daily-report.json`のScheduleノードを編集：

```
毎日21:00に変更: 0 21 * * *
毎日朝8:00に変更: 0 8 * * *
週1回（月曜9:00）: 0 9 * * 1
```

### 4. Slack通知の追加

1. n8nでSlackノードを追加
2. 「Send Email Report」ノードの後に接続
3. Slackワークスペースとチャンネルを設定

### 5. 統計項目の追加

`workflows/trade-journal-main.json`の「Calculate Statistics」ノード（Codeノード）を編集して、新しい統計を追加

例: シャープレシオ、最大ドローダウンなど

---

## Tips & ベストプラクティス

### トレード記録のタイミング

- **推奨**: トレード直後に記録
- **理由**: 感情や考えを忘れないうちに記録できる

### メモの書き方

良いメモの例：
```
✅ 上昇トレンド継続中。レジスタンスブレイクでエントリー。
   利確目標手前で反転の兆しがあったため早めに決済。

❌ トレードした。
```

具体的に以下を記録：
- エントリー理由
- エグジット理由
- その時の心理状態
- 反省点・学んだこと

### タグの使い方

効果的なタグ付け：
- **トレードスタイル**: デイトレード、スイング、スキャルピング
- **戦略**: トレンドフォロー、レンジ、ブレイクアウト
- **結果**: 成功、反省、ルール違反
- **時間帯**: 東京時間、欧州時間、NY時間

### 定期的なレビュー

1. **日次**: その日のトレードを振り返る
2. **週次**: 1週間の傾向を分析（勝率、よく使った通貨ペアなど）
3. **月次**: 月全体のパフォーマンスを評価し、来月の目標を設定

### バックアップ

定期的にデータをバックアップ：
- Google Sheetsからエクスポート（CSV、Excel）
- Notionからエクスポート（Markdown、CSV）

---

## よくある質問

### Q: 手動でNotionやSheetsに追加した場合、どうなる？

A: 手動追加は問題ありませんが、他のサービスには反映されません。Webhookを通じて記録することで、すべてのサービスに同期されます。

### Q: 過去のトレードを遡って記録できる？

A: はい。`timestamp`フィールドに過去の日時を指定すれば可能です。

### Q: チャート画像を自動で添付できる？

A: `chartImageUrl`に画像のURLを指定すればNotion等に表示されます。画像はGoogle Drive、Imgur、CloudinaryなどにアップロードしてURLを取得してください。

### Q: 複数の取引口座を管理できる？

A: タグに「口座A」「口座B」などを追加するか、Notionに「口座」プロパティを追加してください。

### Q: スマホから記録できる？

A: 以下の方法があります：
1. Postmanのモバイルアプリ
2. Notion直接入力（ただし他サービスには未反映）
3. iOSショートカット、Android Taskerなどで自作

---

## サポート

問題や質問があれば：

1. `docs/SETUP.md`のトラブルシューティングを確認
2. GitHubでIssueを作成
3. n8nコミュニティフォーラムで質問

---

Happy Trading!
