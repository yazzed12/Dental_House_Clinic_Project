import Layout from '../components/Layout';
import { FlaskConical, Clock, CheckCircle, AlertTriangle, Search } from 'lucide-react';

const tests = [
  { id: 1, patient: 'Eleanor Voss',   test: 'Complete Blood Count',   ordered: '2026-04-21', result: 'Normal',    status: 'Ready',      tech: 'Lab A' },
  { id: 2, patient: 'Marcus Cole',    test: 'Lipid Panel',            ordered: '2026-04-20', result: 'High LDL',  status: 'Ready',      tech: 'Lab A' },
  { id: 3, patient: 'Oliver Grant',   test: 'CRP Inflammation',       ordered: '2026-04-21', result: '—',         status: 'Processing', tech: 'Lab B' },
  { id: 4, patient: 'Priya Sharma',   test: 'IgE Allergy Panel',      ordered: '2026-04-19', result: 'Elevated',  status: 'Ready',      tech: 'Lab B' },
  { id: 5, patient: 'David Huang',    test: 'Dopamine Levels',        ordered: '2026-04-20', result: '—',         status: 'Pending',    tech: 'Lab C' },
  { id: 6, patient: 'Nina Johansson', test: 'Troponin I',             ordered: '2026-04-21', result: 'Normal',    status: 'Ready',      tech: 'Lab A' },
  { id: 7, patient: 'Kwame Asante',   test: 'ESR Sedimentation Rate', ordered: '2026-04-22', result: '—',         status: 'Pending',    tech: 'Lab C' },
  { id: 8, patient: 'Sofia Reyes',    test: 'Patch Test',             ordered: '2026-04-18', result: 'Positive',  status: 'Ready',      tech: 'Lab B' },
];

const STATUS_STYLE = {
  Ready:      { cls: 'badge badge-success', icon: <CheckCircle size={11} /> },
  Processing: { cls: 'badge badge-primary', icon: <Clock size={11} /> },
  Pending:    { cls: 'badge badge-warning', icon: <Clock size={11} /> },
};

export default function Lab() {
  const ready      = tests.filter(t => t.status === 'Ready').length;
  const processing = tests.filter(t => t.status === 'Processing').length;
  const pending    = tests.filter(t => t.status === 'Pending').length;

  return (
    <Layout pageTitle="Laboratory" pageSubtitle={`${tests.length} test orders`}>
      <div className="grid-4 stagger animate-fadeIn" style={{ marginBottom: 'var(--sp-xl)' }}>
        {[
          { label: 'Total Tests', value: tests.length, color: '#3b82f6' },
          { label: 'Ready',       value: ready,         color: '#10b981' },
          { label: 'Processing',  value: processing,    color: '#06b6d4' },
          { label: 'Pending',     value: pending,       color: '#f59e0b' },
        ].map(({ label, value, color }) => (
          <div key={label} className="card" style={{ padding: '16px 20px', textAlign: 'center' }}>
            <div style={{ fontSize: '1.8rem', fontWeight: 800, color }}>{value}</div>
            <div style={{ fontSize: '0.75rem', color: 'var(--clr-text-muted)', fontWeight: 600, textTransform: 'uppercase' }}>{label}</div>
          </div>
        ))}
      </div>

      <div style={{ display: 'flex', gap: 10, marginBottom: 'var(--sp-lg)' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 200 }}>
          <Search size={14} style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-text-muted)' }} />
          <input className="form-input" style={{ paddingLeft: 36, borderRadius: 'var(--r-full)' }} placeholder="Search lab tests…" />
        </div>
        <button className="btn btn-primary btn-sm"><FlaskConical size={14} /> Order New Test</button>
      </div>

      <div className="card animate-fadeIn" style={{ padding: 0, overflow: 'hidden' }}>
        <div className="table-wrapper" style={{ borderRadius: 0, border: 'none' }}>
          <table>
            <thead><tr>
              <th>#</th><th>Patient</th><th>Test Name</th>
              <th>Ordered</th><th>Result</th><th>Lab</th><th>Status</th>
            </tr></thead>
            <tbody>
              {tests.map(t => {
                const s = STATUS_STYLE[t.status];
                return (
                  <tr key={t.id}>
                    <td style={{ color: 'var(--clr-text-muted)', fontFamily: 'var(--font-mono)' }}>#{t.id.toString().padStart(3,'0')}</td>
                    <td style={{ fontWeight: 600, color: 'var(--clr-text-primary)' }}>{t.patient}</td>
                    <td style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                      <FlaskConical size={13} style={{ color: 'var(--clr-cyan)' }} /> {t.test}
                    </td>
                    <td style={{ fontFamily: 'var(--font-mono)', fontSize: '0.8rem' }}>{t.ordered}</td>
                    <td style={{ fontWeight: 600, color: t.result === '—' ? 'var(--clr-text-muted)' : t.result === 'Normal' ? 'var(--clr-success)' : 'var(--clr-warning)' }}>
                      {t.result}
                    </td>
                    <td><span className="badge badge-purple">{t.tech}</span></td>
                    <td><span className={s.cls} style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>{s.icon}{t.status}</span></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </Layout>
  );
}
