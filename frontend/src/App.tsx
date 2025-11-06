import React from 'react';
import { BrowserRouter as Router, Routes, Route, Link, useLocation } from 'react-router-dom';
import { Dashboard } from './pages/Dashboard';
import { Trades } from './pages/Trades';
import { Journal } from './pages/Journal';

const Navigation: React.FC = () => {
  const location = useLocation();

  const isActive = (path: string) => {
    return location.pathname === path;
  };

  return (
    <nav className="bg-white shadow-lg">
      <div className="max-w-7xl mx-auto px-4">
        <div className="flex justify-between h-16">
          <div className="flex space-x-8">
            <Link to="/" className="flex items-center">
              <span className="text-xl font-bold text-blue-600">トレーディングジャーナル</span>
            </Link>
            <div className="flex space-x-4">
              <Link
                to="/"
                className={`inline-flex items-center px-3 pt-1 border-b-2 text-sm font-medium ${
                  isActive('/')
                    ? 'border-blue-500 text-gray-900'
                    : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700'
                }`}
              >
                ダッシュボード
              </Link>
              <Link
                to="/trades"
                className={`inline-flex items-center px-3 pt-1 border-b-2 text-sm font-medium ${
                  isActive('/trades')
                    ? 'border-blue-500 text-gray-900'
                    : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700'
                }`}
              >
                トレード記録
              </Link>
              <Link
                to="/journal"
                className={`inline-flex items-center px-3 pt-1 border-b-2 text-sm font-medium ${
                  isActive('/journal')
                    ? 'border-blue-500 text-gray-900'
                    : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700'
                }`}
              >
                トレード日記
              </Link>
            </div>
          </div>
        </div>
      </div>
    </nav>
  );
};

function App() {
  return (
    <Router>
      <div className="min-h-screen bg-gray-50">
        <Navigation />
        <main className="max-w-7xl mx-auto px-4 py-8">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/trades" element={<Trades />} />
            <Route path="/journal" element={<Journal />} />
          </Routes>
        </main>
      </div>
    </Router>
  );
}

export default App;
