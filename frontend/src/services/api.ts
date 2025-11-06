import axios from 'axios';
import { Trade, JournalEntry, TradeStats } from '../types';

const API_BASE_URL = '/api';

export const api = {
  // Trades
  getTrades: () => axios.get<Trade[]>(`${API_BASE_URL}/trades`),
  getTrade: (id: number) => axios.get<Trade>(`${API_BASE_URL}/trades/${id}`),
  createTrade: (trade: Trade) => axios.post(`${API_BASE_URL}/trades`, trade),
  updateTrade: (id: number, trade: Partial<Trade>) => axios.put(`${API_BASE_URL}/trades/${id}`, trade),
  deleteTrade: (id: number) => axios.delete(`${API_BASE_URL}/trades/${id}`),
  getTradeStats: () => axios.get<TradeStats>(`${API_BASE_URL}/trades/stats`),

  // Journal
  getJournalEntries: () => axios.get<JournalEntry[]>(`${API_BASE_URL}/journal`),
  getJournalEntry: (id: number) => axios.get<JournalEntry>(`${API_BASE_URL}/journal/${id}`),
  getJournalEntriesByTrade: (tradeId: number) => axios.get<JournalEntry[]>(`${API_BASE_URL}/journal/trade/${tradeId}`),
  createJournalEntry: (entry: JournalEntry) => axios.post(`${API_BASE_URL}/journal`, entry),
  updateJournalEntry: (id: number, entry: Partial<JournalEntry>) => axios.put(`${API_BASE_URL}/journal/${id}`, entry),
  deleteJournalEntry: (id: number) => axios.delete(`${API_BASE_URL}/journal/${id}`),
};
