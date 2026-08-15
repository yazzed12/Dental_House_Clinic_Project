import Layout from '../components/Layout';
import { FileText, TrendingUp, Download, Filter } from 'lucide-react';
import { useData } from '../context/DataContext';

const STATUS = {
  Final:   'badge badge-success',
  Pending: 'badge badge-warning',
  Draft:   'badge badge-cyan',
};

export default function Records() {
  const { records } = useData();
  return (
    <Layout pageTitle="Medical Records" pageSubtitle={`${records?.length || 0} documents`}>
      {/* Summary */}
      <div className="grid-3 stagger animate-fadeIn" style={{ marginBottom: 'var(--sp-xl)' }}>
        {[
          { label: 'Total Records', value: records.length,                                       color: '#3b82f6' },
          { label: 'Finalized',     value: records.filter(r => r.status === 'Final').length,      color: '#10b981' },
          { label: 'Pending Review',value: records.filter(r => r.status === 'Pending').length,    color: '#f59e0b' },
        ].map(({ label, value, color }) => (
          <div key={label} className="card" style={{ padding: '16px 20px', textAlign: 'center' }}>
            <div style={{ fontSize: '1.8rem', fontWeight: 800, color }}>{value}</div>
            <div style={{ fontSize: '0.75rem', color: 'var(--clr-text-muted)', fontWeight: 600, textTransform: 'uppercase' }}>{label}</div>
          </div>
        ))}
      </div>

      {/* Controls */}
      <div style={{ display: 'flex', gap: 10, marginBottom: 'var(--sp-lg)', flexWrap: 'wrap' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 200 }}>
          <FileText size={14} style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-text-muted)' }} />
          <input className="form-input" style={{ paddingLeft: 36, borderRadius: 'var(--r-full)' }} placeholder="Search records…" />
        </div>
        <button className="btn btn-secondary btn-sm"><Filter size={13} /> Filter</button>
        <button className="btn btn-primary btn-sm"><Download size={13} /> Export All</button>
      </div>

      {/* Table */}
      <div className="card animate-fadeIn" style={{ padding: 0, overflow: 'hidden' }}>
        <div className="table-wrapper" style={{ borderRadius: 0, border: 'none' }}>
          <table>
            <thead><tr>
              <th>#</th><th>Patient</th><th>Record Type</th>
              <th>Doctor</th><th>Date</th><th>Size</th><th>Status</th><th>Action</th>
            </tr></thead>
            <tbody>
              {records.map(r => (
                <tr key={r.id}>
                  <td style={{ color: 'var(--clr-text-muted)', fontFamily: 'var(--font-mono)' }}>#{r.id.toString().padStart(3,'0')}</td>
                  <td style={{ fontWeight: 600, color: 'var(--clr-text-primary)' }}>{r.patient}</td>
                  <td>
                    <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                      <FileText size={13} style={{ color: 'var(--clr-primary)' }} /> {r.type}
                    </span>
                  </td>
                  <td>{r.doctor}</td>
                  <td style={{ fontFamily: 'var(--font-mono)', fontSize: '0.8rem' }}>{r.date}</td>
                  <td style={{ color: 'var(--clr-text-muted)', fontFamily: 'var(--font-mono)', fontSize: '0.8rem' }}>{r.size}</td>
                  <td><span className={STATUS[r.status]}>{r.status}</span></td>
                  <td>
                    <button className="btn btn-sm btn-secondary" style={{ gap: 5 }}>
                      <Download size={12} /> Download
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </Layout>
  );
}
