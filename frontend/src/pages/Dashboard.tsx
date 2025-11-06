import React, { useEffect, useState } from 'react';
import { api } from '../services/api';
import { TradeStats } from '../types';

export const Dashboard: React.FC = () => {
  const [stats, setStats] = useState<TradeStats | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadStats();
  }, []);

  const loadStats = async () => {
    try {
      const response = await api.getTradeStats();
      setStats(response.data);
    } catch (error) {
      console.error('Failed to load stats:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return <div className="text-center py-8">読み込み中...</div>;
  }

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold text-gray-900">ダッシュボード</h1>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="bg-white p-6 rounded-lg shadow-md">
          <h3 className="text-lg font-semibold text-gray-700 mb-2">総トレード数</h3>
          <p className="text-3xl font-bold text-blue-600">{stats?.totalTrades || 0}</p>
        </div>

        <div className="bg-white p-6 rounded-lg shadow-md">
          <h3 className="text-lg font-semibold text-gray-700 mb-2">総損益</h3>
          <p className={`text-3xl font-bold ${(stats?.totalProfit || 0) >= 0 ? 'text-green-600' : 'text-red-600'}`}>
            {(stats?.totalProfit || 0).toFixed(2)}
          </p>
        </div>

        <div className="bg-white p-6 rounded-lg shadow-md">
          <h3 className="text-lg font-semibold text-gray-700 mb-2">勝率</h3>
          <p className="text-3xl font-bold text-purple-600">{(stats?.winRate || 0).toFixed(1)}%</p>
        </div>
      </div>

      <div className="bg-white p-6 rounded-lg shadow-md">
        <h2 className="text-xl font-semibold text-gray-800 mb-4">ようこそ</h2>
        <p className="text-gray-600">
          トレーディングジャーナルへようこそ。このアプリでトレード記録と感情を管理し、
          自己分析を深めることができます。
        </p>
      </div>
    </div>
  );
};
