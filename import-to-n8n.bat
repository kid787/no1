@echo off
REM n8nにワークフローをインポートするスクリプト（Windows用）
REM ローカルn8n (http://localhost:5678) 用

SET N8N_URL=http://localhost:5678
SET API_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhZmUxZTJiZi1jMTBjLTRhNTctOGIwYi1hNmY3Y2VlNDA2MWQiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwiaWF0IjoxNzYyMjU0MTg2fQ.DkLJXXg0GJhNpBZ1YErJoJsePtHhqEEvMwtnS8wq1UE

echo === n8nワークフローインポートスクリプト ===
echo.

REM カレントディレクトリをスクリプトの場所に変更
cd /d %~dp0

echo メインワークフローをインポート中...
curl -X POST %N8N_URL%/api/v1/workflows ^
  -H "Content-Type: application/json" ^
  -H "X-N8N-API-KEY: %API_KEY%" ^
  -d @workflows/trade-journal-main.json

echo.
echo.

echo 日次レポートワークフローをインポート中...
curl -X POST %N8N_URL%/api/v1/workflows ^
  -H "Content-Type: application/json" ^
  -H "X-N8N-API-KEY: %API_KEY%" ^
  -d @workflows/daily-report.json

echo.
echo.
echo === インポート完了 ===
echo ブラウザで http://localhost:5678/home/workflows を開いて確認してください
echo.
pause
