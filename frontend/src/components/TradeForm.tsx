import React, { useState } from 'react';
import { Trade } from '../types';

interface TradeFormProps {
  onSubmit: (trade: Trade) => void;
  initialData?: Trade;
  onCancel?: () => void;
}

export const TradeForm: React.FC<TradeFormProps> = ({ onSubmit, initialData, onCancel }) => {
  const [formData, setFormData] = useState<Trade>(initialData || {
    date: new Date().toISOString().split('T')[0],
    symbol: '',
    side: 'buy',
    entry_price: 0,
    exit_price: undefined,
    quantity: 0,
    profit_loss: undefined,
    status: 'open'
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(formData);
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: ['entry_price', 'exit_price', 'quantity', 'profit_loss'].includes(name)
        ? parseFloat(value) || undefined
        : value
    }));
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4 bg-white p-6 rounded-lg shadow-md">
      <div>
        <label className="block text-sm font-medium text-gray-700">日付</label>
        <input
          type="date"
          name="date"
          value={formData.date}
          onChange={handleChange}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 p-2 border"
          required
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700">銘柄/通貨ペア</label>
        <input
          type="text"
          name="symbol"
          value={formData.symbol}
          onChange={handleChange}
          placeholder="例: BTC/USD, USDJPY"
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 p-2 border"
          required
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700">売買区分</label>
        <select
          name="side"
          value={formData.side}
          onChange={handleChange}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 p-2 border"
        >
          <option value="buy">買い</option>
          <option value="sell">売り</option>
        </select>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">エントリー価格</label>
          <input
            type="number"
            name="entry_price"
            value={formData.entry_price}
            onChange={handleChange}
            step="0.01"
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 p-2 border"
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">決済価格</label>
          <input
            type="number"
            name="exit_price"
            value={formData.exit_price || ''}
            onChange={handleChange}
            step="0.01"
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 p-2 border"
          />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">数量</label>
          <input
            type="number"
            name="quantity"
            value={formData.quantity}
            onChange={handleChange}
            step="0.01"
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 p-2 border"
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700">損益</label>
          <input
            type="number"
            name="profit_loss"
            value={formData.profit_loss || ''}
            onChange={handleChange}
            step="0.01"
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 p-2 border"
          />
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700">ステータス</label>
        <select
          name="status"
          value={formData.status}
          onChange={handleChange}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 p-2 border"
        >
          <option value="open">オープン</option>
          <option value="closed">クローズ</option>
        </select>
      </div>

      <div className="flex gap-2">
        <button
          type="submit"
          className="flex-1 bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
        >
          {initialData ? '更新' : '登録'}
        </button>
        {onCancel && (
          <button
            type="button"
            onClick={onCancel}
            className="flex-1 bg-gray-300 text-gray-700 px-4 py-2 rounded-md hover:bg-gray-400 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2"
          >
            キャンセル
          </button>
        )}
      </div>
    </form>
  );
};
