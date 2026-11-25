'use client';

import { useState } from 'react';

type Health = { status: string; uptime: number; timestamp: string };

export default function Home() {
  const [health, setHealth] = useState<Health | null>(null);
  const [loading, setLoading] = useState(false);

  async function checkHealth() {
    setLoading(true);
    try {
      const res = await fetch('/api/health', { cache: 'no-store' });
      setHealth(await res.json());
    } catch {
      setHealth(null);
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="card">
      <div className="badge">
        <span className="dot" />
        Live on EC2
      </div>

      <h1>Next.js deployed with GitHub Actions</h1>
      <p>
        This app is built inside GitHub Actions and the standalone output is
        synced to a small EC2 instance. Nothing is compiled on the server, so a
        1 vCPU / 2 GB box is plenty.
      </p>

      <div className="steps">
        <div className="step">
          <span>1</span>
          <span>Push to <code>main</code> → CI installs and builds the app.</span>
        </div>
        <div className="step">
          <span>2</span>
          <span>CI rsyncs the standalone build to the EC2 over SSH.</span>
        </div>
        <div className="step">
          <span>3</span>
          <span>PM2 reloads the new build with zero manual steps.</span>
        </div>
      </div>

      <div className="actions">
        <button onClick={checkHealth} disabled={loading}>
          {loading ? 'Checking…' : 'Check health'}
        </button>
        {health && (
          <span className="check">
            {health.status} · up {Math.floor(health.uptime)}s
          </span>
        )}
      </div>

      <footer className="footer">v1.0.2 · served via Nginx on mirror1.downly.sbs</footer>
    </main>
  );
}
