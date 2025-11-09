# n8nにワークフローをインポートするスクリプト（PowerShell版）
# ローカルn8n (http://localhost:5678) 用

$N8N_URL = "http://localhost:5678"
$API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhZmUxZTJiZi1jMTBjLTRhNTctOGIwYi1hNmY3Y2VlNDA2MWQiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwiaWF0IjoxNzYyMjU0MTg2fQ.DkLJXXg0GJhNpBZ1YErJoJsePtHhqEEvMwtnS8wq1UE"

Write-Host "=== n8nワークフローインポートスクリプト ===" -ForegroundColor Cyan
Write-Host ""

# スクリプトのディレクトリに移動
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# ヘッダーの準備
$headers = @{
    "Content-Type" = "application/json"
    "X-N8N-API-KEY" = $API_KEY
}

# メインワークフローのインポート
Write-Host "📊 Trade Journal Main Workflow をインポート中..." -ForegroundColor Yellow
try {
    $mainWorkflow = Get-Content -Path "workflows/trade-journal-main.json" -Raw
    $response1 = Invoke-RestMethod -Uri "$N8N_URL/api/v1/workflows" -Method Post -Headers $headers -Body $mainWorkflow
    Write-Host "✅ メインワークフローがインポートされました (ID: $($response1.id))" -ForegroundColor Green
    Write-Host "   $N8N_URL/workflow/$($response1.id)" -ForegroundColor Gray
} catch {
    Write-Host "❌ メインワークフローのインポートに失敗しました: $_" -ForegroundColor Red
}

Write-Host ""

# 日次レポートワークフローのインポート
Write-Host "📧 Daily Report Workflow をインポート中..." -ForegroundColor Yellow
try {
    $dailyWorkflow = Get-Content -Path "workflows/daily-report.json" -Raw
    $response2 = Invoke-RestMethod -Uri "$N8N_URL/api/v1/workflows" -Method Post -Headers $headers -Body $dailyWorkflow
    Write-Host "✅ 日次レポートワークフローがインポートされました (ID: $($response2.id))" -ForegroundColor Green
    Write-Host "   $N8N_URL/workflow/$($response2.id)" -ForegroundColor Gray
} catch {
    Write-Host "❌ 日次レポートワークフローのインポートに失敗しました: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== インポート完了 ===" -ForegroundColor Cyan
Write-Host "ブラウザで http://localhost:5678/home/workflows を開いて確認してください" -ForegroundColor White
Write-Host ""
Read-Host "Enterキーを押して終了"
