#!/bin/bash

# n8nにワークフローをインポートするスクリプト
# ローカルn8n (http://localhost:5678) 用

N8N_URL="http://localhost:5678"
WORKFLOWS_DIR="/home/user/no1/workflows"

echo "=== n8nワークフローインポートスクリプト ==="
echo ""

# メインワークフローのインポート
echo "📊 Trade Journal Main Workflow をインポート中..."
curl -X POST "${N8N_URL}/api/v1/workflows" \
  -H "Content-Type: application/json" \
  -d @"${WORKFLOWS_DIR}/trade-journal-main.json" \
  2>/dev/null | jq -r '.id' > /tmp/workflow1_id.txt

if [ -s /tmp/workflow1_id.txt ]; then
  WORKFLOW1_ID=$(cat /tmp/workflow1_id.txt)
  echo "✅ メインワークフローがインポートされました (ID: ${WORKFLOW1_ID})"
  echo "   ${N8N_URL}/workflow/${WORKFLOW1_ID}"
else
  echo "❌ メインワークフローのインポートに失敗しました"
fi

echo ""

# 日次レポートワークフローのインポート
echo "📧 Daily Report Workflow をインポート中..."
curl -X POST "${N8N_URL}/api/v1/workflows" \
  -H "Content-Type: application/json" \
  -d @"${WORKFLOWS_DIR}/daily-report.json" \
  2>/dev/null | jq -r '.id' > /tmp/workflow2_id.txt

if [ -s /tmp/workflow2_id.txt ]; then
  WORKFLOW2_ID=$(cat /tmp/workflow2_id.txt)
  echo "✅ 日次レポートワークフローがインポートされました (ID: ${WORKFLOW2_ID})"
  echo "   ${N8N_URL}/workflow/${WORKFLOW2_ID}"
else
  echo "❌ 日次レポートワークフローのインポートに失敗しました"
fi

echo ""
echo "=== インポート完了 ==="
echo "ブラウザで ${N8N_URL}/home/workflows を開いて確認してください"
