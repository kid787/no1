import React, { useEffect, useState } from 'react';
import { api } from '../services/api';
import { JournalEntry } from '../types';
import { JournalForm } from '../components/JournalForm';

export const Journal: React.FC = () => {
  const [entries, setEntries] = useState<JournalEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editingEntry, setEditingEntry] = useState<JournalEntry | null>(null);

  useEffect(() => {
    loadEntries();
  }, []);

  const loadEntries = async () => {
    try {
      const response = await api.getJournalEntries();
      setEntries(response.data);
    } catch (error) {
      console.error('Failed to load journal entries:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (entry: JournalEntry) => {
    try {
      if (editingEntry?.id) {
        await api.updateJournalEntry(editingEntry.id, entry);
      } else {
        await api.createJournalEntry(entry);
      }
      await loadEntries();
      setShowForm(false);
      setEditingEntry(null);
    } catch (error) {
      console.error('Failed to save journal entry:', error);
    }
  };

  const handleDelete = async (id: number) => {
    if (!confirm('このエントリーを削除しますか？')) return;
    try {
      await api.deleteJournalEntry(id);
      await loadEntries();
    } catch (error) {
      console.error('Failed to delete journal entry:', error);
    }
  };

  const handleEdit = (entry: JournalEntry) => {
    setEditingEntry(entry);
    setShowForm(true);
  };

  const handleCancel = () => {
    setShowForm(false);
    setEditingEntry(null);
  };

  const getEntryTypeLabel = (type: string) => {
    const labels: Record<string, string> = {
      general: '一般',
      before: 'トレード前',
      during: 'トレード中',
      after: 'トレード後'
    };
    return labels[type] || type;
  };

  const getEntryTypeColor = (type: string) => {
    const colors: Record<string, string> = {
      general: 'bg-gray-100 text-gray-800',
      before: 'bg-blue-100 text-blue-800',
      during: 'bg-yellow-100 text-yellow-800',
      after: 'bg-green-100 text-green-800'
    };
    return colors[type] || 'bg-gray-100 text-gray-800';
  };

  if (loading) {
    return <div className="text-center py-8">読み込み中...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-3xl font-bold text-gray-900">トレード日記</h1>
        <button
          onClick={() => setShowForm(!showForm)}
          className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700"
        >
          {showForm ? 'フォームを閉じる' : '新規エントリー'}
        </button>
      </div>

      {showForm && (
        <JournalForm
          onSubmit={handleSubmit}
          initialData={editingEntry || undefined}
          onCancel={handleCancel}
        />
      )}

      <div className="space-y-4">
        {entries.map((entry) => (
          <div key={entry.id} className="bg-white p-6 rounded-lg shadow-md">
            <div className="flex justify-between items-start mb-4">
              <div className="flex items-center gap-3">
                <span className={`px-3 py-1 rounded-full text-xs font-semibold ${getEntryTypeColor(entry.entry_type)}`}>
                  {getEntryTypeLabel(entry.entry_type)}
                </span>
                {entry.emotion && (
                  <span className="text-sm text-gray-600">
                    感情: <span className="font-semibold">{entry.emotion}</span>
                  </span>
                )}
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => handleEdit(entry)}
                  className="text-blue-600 hover:text-blue-900 text-sm"
                >
                  編集
                </button>
                <button
                  onClick={() => entry.id && handleDelete(entry.id)}
                  className="text-red-600 hover:text-red-900 text-sm"
                >
                  削除
                </button>
              </div>
            </div>
            <p className="text-gray-800 whitespace-pre-wrap mb-2">{entry.content}</p>
            <p className="text-xs text-gray-500">
              {entry.created_at && new Date(entry.created_at).toLocaleString('ja-JP')}
            </p>
          </div>
        ))}
      </div>

      {entries.length === 0 && (
        <div className="bg-white p-8 rounded-lg shadow-md text-center text-gray-500">
          まだ日記エントリーがありません
        </div>
      )}
    </div>
  );
};
