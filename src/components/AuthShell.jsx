import React from 'react';
import { Activity } from 'lucide-react';

export default function AuthShell({ children }) {
  return (
    <main className="auth-shell">
      <section className="auth-panel">
        <div className="auth-brand auth-brand-centered" style={{ gap: '12px', marginBottom: '8px' }}>
          <span className="auth-logo" style={{ width: '46px', height: '46px' }}>
            <Activity size={28} />
          </span>
          <span style={{ fontSize: '1.4rem' }}>Smart Dental Clinic</span>
        </div>
        {children}
      </section>
    </main>
  );
}
