import React, { useEffect, useState } from 'react';
import { api } from '../services/api';
import { Trade } from '../types';
import { TradeForm } from '../components/TradeForm';

export const Trades: React.FC = () => {
  const [trades, setTrades] = useState<Trade[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editingTrade, setEditingTrade] = useState<Trade | null>(null);

  useEffect(() => {
    loadTrades();
  }, []);

  const loadTrades = async () => {
    try {
      const response = await api.getTrades();
      setTrades(response.data);
    } catch (error) {
      console.error('Failed to load trades:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (trade: Trade) => {
    try {
      if (editingTrade?.id) {
        await api.updateTrade(editingTrade.id, trade);
      } else {
        await api.createTrade(trade);
      }
      await loadTrades();
      setShowForm(false);
      setEditingTrade(null);
    } catch (error) {
      console.error('Failed to save trade:', error);
    }
  };

  const handleDelete = async (id: number) => {
    if (!confirm('このトレードを削除しますか？')) return;
    try {
      await api.deleteTrade(id);
      await loadTrades();
    } catch (error) {
      console.error('Failed to delete trade:', error);
    }
  };

  const handleEdit = (trade: Trade) => {
    setEditingTrade(trade);
    setShowForm(true);
  };

  const handleCancel = () => {
    setShowForm(false);
    setEditingTrade(null);
  };

  if (loading) {
    return <div className="text-center py-8">読み込み中...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-3xl font-bold text-gray-900">トレード記録</h1>
        <button
          onClick={() => setShowForm(!showForm)}
          className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700"
        >
          {showForm ? 'フォームを閉じる' : '新規トレード'}
        </button>
      </div>

      {showForm && (
        <TradeForm
          onSubmit={handleSubmit}
          initialData={editingTrade || undefined}
          onCancel={handleCancel}
        />
      )}

      <div className="bg-white rounded-lg shadow-md overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">日付</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">銘柄</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">売買</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">エントリー</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">決済</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">数量</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">損益</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ステータス</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">操作</th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {trades.map((trade) => (
                <tr key={trade.id}>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{trade.date}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{trade.symbol}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm">
                    <span className={`px-2 py-1 rounded-full text-xs font-semibold ${
                      trade.side === 'buy' ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'
                    }`}>
                      {trade.side === 'buy' ? '買い' : '売り'}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{trade.entry_price}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{trade.exit_price || '-'}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{trade.quantity}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm">
                    <span className={`font-semibold ${
                      (trade.profit_loss || 0) >= 0 ? 'text-green-600' : 'text-red-600'
                    }`}>
                      {trade.profit_loss?.toFixed(2) || '-'}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm">
                    <span className={`px-2 py-1 rounded-full text-xs font-semibold ${
                      trade.status === 'open' ? 'bg-blue-100 text-blue-800' : 'bg-gray-100 text-gray-800'
                    }`}>
                      {trade.status === 'open' ? 'オープン' : 'クローズ'}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <button
                      onClick={() => handleEdit(trade)}
                      className="text-blue-600 hover:text-blue-900 mr-3"
                    >
                      編集
                    </button>
                    <button
                      onClick={() => trade.id && handleDelete(trade.id)}
                      className="text-red-600 hover:text-red-900"
                    >
                      削除
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {trades.length === 0 && (
          <div className="text-center py-8 text-gray-500">
            まだトレード記録がありません
          </div>
        )}
      </div>
    </div>
  );
};
