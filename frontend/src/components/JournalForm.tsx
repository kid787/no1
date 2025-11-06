import React, { useState } from 'react';
import { JournalEntry } from '../types';

interface JournalFormProps {
  onSubmit: (entry: JournalEntry) => void;
  tradeId?: number;
  initialData?: JournalEntry;
  onCancel?: () => void;
}

export const JournalForm: React.FC<JournalFormProps> = ({ onSubmit, tradeId, initialData, onCancel }) => {
  const [formData, setFormData] = useState<JournalEntry>(initialData || {
    trade_id: tradeId,
    entry_type: 'general',
    emotion: '',
    content: ''
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(formData);
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value
    }));
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4 bg-white p-6 rounded-lg shadow-md">
      <div>
        <label className="block text-sm font-medium text-gray-700">エントリータイプ</label>
        <select
          name="entry_type"
          value={formData.entry_type}
          onChange={handleChange}
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 p-2 border"
        >
          <option value="general">一般</option>
          <option value="before">トレード前</option>
          <option value="during">トレード中</option>
          <option value="after">トレード後</option>
        </select>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700">感情</label>
        <input
          type="text"
          name="emotion"
          value={formData.emotion}
          onChange={handleChange}
          placeholder="例: 不安、興奮、冷静"
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 p-2 border"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700">内容</label>
        <textarea
          name="content"
          value={formData.content}
          onChange={handleChange}
          rows={6}
          placeholder="今の気持ちや考えを自由に記録..."
          className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 p-2 border"
          required
        />
      </div>

      <div className="flex gap-2">
        <button
          type="submit"
          className="flex-1 bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
        >
          {initialData ? '更新' : '記録'}
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
