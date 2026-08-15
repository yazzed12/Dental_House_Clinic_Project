import Layout from '../components/Layout';
import { BarChart2, TrendingUp, Users, Calendar, DollarSign, Activity, Download } from 'lucide-react';
import { patientsByDept, weeklyAppointments } from '../data/mockData';

/* ── Horizontal Bar Chart ────────────────────────────────────── */
function HBar({ label, value, max, color }) {
  const pct = Math.round((value / max) * 100);
  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
        <span style={{ fontSize: '0.8rem', color: 'var(--clr-text-secondary)', fontWeight: 500 }}>{label}</span>
        <span style={{ fontSize: '0.8rem', fontWeight: 700, color: 'var(--clr-text-primary)' }}>{value} <span style={{ color: 'var(--clr-text-muted)', fontWeight: 400 }}>({pct}%)</span></span>
      </div>
      <div className="progress-wrap">
        <div className="progress-bar" style={{ width: `${pct}%`, background: `linear-gradient(90deg, ${color}, ${color}aa)` }} />
      </div>
    </div>
  );
}

/* ── Mini Vertical Bar ───────────────────────────────────────── */
function VBar({ data, color = 'var(--grad-primary)' }) {
  const max = Math.max(...data.map(d => d.count));
  return (
    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 6, height: 80 }}>
      {data.map(({ day, count }) => (
        <div key={day} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
          <div style={{ width: '100%', borderRadius: 3, background: color, height: `${(count / max) * 70}px`, transition: 'height 0.8s ease' }} />
          <span style={{ fontSize: '0.6rem', color: 'var(--clr-text-muted)', fontWeight: 600 }}>{day}</span>
        </div>
      ))}
    </div>
  );
}

/* ── KPI Tile ────────────────────────────────────────────────── */
function KpiTile({ icon: Icon, label, value, change, color }) {
  const up = change >= 0;
  return (
    <div className="card" style={{ padding: '16px 20px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
        <div style={{ width: 36, height: 36, borderRadius: 'var(--r-md)', background: `${color}22`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon size={16} color={color} />
        </div>
        <span style={{ fontSize: '0.72rem', color: 'var(--clr-text-muted)', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.05em' }}>{label}</span>
      </div>
      <div style={{ fontSize: '1.6rem', fontWeight: 800, color, lineHeight: 1 }}>{value}</div>
      <div style={{ fontSize: '0.72rem', marginTop: 4, color: up ? 'var(--clr-success)' : 'var(--clr-danger)', display: 'flex', alignItems: 'center', gap: 3, fontWeight: 600 }}>
        <TrendingUp size={11} /> {up ? '+' : ''}{change}% vs last month
      </div>
    </div>
  );
}

/* ── Monthly Trend Data ──────────────────────────────────────── */
const monthlyRevenue = [
  { month: 'Nov', value: 68000 },
  { month: 'Dec', value: 72000 },
  { month: 'Jan', value: 65000 },
  { month: 'Feb', value: 78000 },
  { month: 'Mar', value: 81000 },
  { month: 'Apr', value: 84200 },
];

/* ── Reports Page ────────────────────────────────────────────── */
export default function Reports() {
  const maxDept    = Math.max(...patientsByDept.map(d => d.count));
  const maxRevenue = Math.max(...monthlyRevenue.map(d => d.value));

  return (
    <Layout pageTitle="Reports" pageSubtitle="Analytics and performance insights">

      {/* ── KPI Row ── */}
      <div className="grid-4 stagger animate-fadeIn" style={{ marginBottom: 'var(--sp-xl)' }}>
        <KpiTile icon={Users}    label="New Patients"   value="148"    change={14}  color="#3b82f6" />
        <KpiTile icon={Calendar} label="Appointments"   value="295"    change={8}   color="#10b981" />
        <KpiTile icon={DollarSign} label="Revenue"      value="$84.2K" change={7}   color="#f59e0b" />
        <KpiTile icon={Activity} label="Avg. Wait Time" value="18 min" change={-12} color="#8b5cf6" />
      </div>

      {/* ── Charts Row ── */}
      <div className="grid-2 animate-fadeIn" style={{ marginBottom: 'var(--sp-xl)', animationDelay: '100ms' }}>

        {/* Patients by Dept */}
        <div className="card">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 'var(--sp-lg)' }}>
            <div>
              <h3 style={{ fontSize: '0.95rem', fontWeight: 700 }}>Patients by Department</h3>
              <p style={{ fontSize: '0.75rem', margin: 0 }}>April 2026</p>
            </div>
            <button className="btn btn-sm btn-secondary"><Download size={12} /></button>
          </div>
          {patientsByDept.map(d => (
            <HBar key={d.dept} label={d.dept} value={d.count} max={maxDept} color={d.color} />
          ))}
        </div>

        {/* Weekly Appointments Trend */}
        <div className="card">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 'var(--sp-lg)' }}>
            <div>
              <h3 style={{ fontSize: '0.95rem', fontWeight: 700 }}>Weekly Appointments</h3>
              <p style={{ fontSize: '0.75rem', margin: 0 }}>Current week · 295 total</p>
            </div>
            <button className="btn btn-sm btn-secondary"><Download size={12} /></button>
          </div>
          <VBar data={weeklyAppointments} color="var(--grad-primary)" />

          {/* Summary mini-grid */}
          <div className="grid-3" style={{ gap: 8, marginTop: 'var(--sp-md)' }}>
            {[
              { label: 'Peak Day', value: 'Thursday', sub: '67 appointments' },
              { label: 'Avg / Day', value: '42', sub: 'appointments' },
              { label: 'Slowest', value: 'Sunday', sub: '14 appointments' },
            ].map(({ label, value, sub }) => (
              <div key={label} style={{ padding: '10px', background: 'var(--clr-surface-2)', borderRadius: 'var(--r-md)', textAlign: 'center', border: '1px solid var(--clr-border)' }}>
                <div style={{ fontSize: '0.7rem', color: 'var(--clr-text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em' }}>{label}</div>
                <div style={{ fontSize: '0.95rem', fontWeight: 800, color: 'var(--clr-text-primary)', marginTop: 3 }}>{value}</div>
                <div style={{ fontSize: '0.65rem', color: 'var(--clr-text-muted)' }}>{sub}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* ── Revenue Trend ── */}
      <div className="card animate-fadeIn" style={{ animationDelay: '200ms' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 'var(--sp-lg)' }}>
          <div>
            <h3 style={{ fontSize: '0.95rem', fontWeight: 700 }}>Revenue Trend</h3>
            <p style={{ fontSize: '0.75rem', margin: 0 }}>Last 6 months</p>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <button className="btn btn-sm btn-secondary"><Download size={12} /> Export</button>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'flex-end', gap: 12, height: 100 }}>
          {monthlyRevenue.map(({ month, value }, i) => {
            const isLast = i === monthlyRevenue.length - 1;
            const pct = (value / maxRevenue) * 88;
            return (
              <div key={month} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
                <div style={{ fontSize: '0.7rem', fontWeight: 700, color: isLast ? 'var(--clr-primary)' : 'var(--clr-text-muted)' }}>
                  ${(value / 1000).toFixed(0)}K
                </div>
                <div style={{
                  width: '100%', borderRadius: '4px 4px 0 0',
                  height: `${pct}px`,
                  background: isLast ? 'var(--grad-primary)' : 'var(--clr-surface-3)',
                  border: isLast ? '1px solid rgba(59,130,246,0.4)' : '1px solid var(--clr-border)',
                  boxShadow: isLast ? '0 0 20px rgba(59,130,246,0.25)' : 'none',
                  transition: 'height 0.8s ease',
                }} />
                <span style={{ fontSize: '0.72rem', color: isLast ? 'var(--clr-primary)' : 'var(--clr-text-muted)', fontWeight: isLast ? 700 : 400 }}>{month}</span>
              </div>
            );
          })}
        </div>

        {/* Revenue insight */}
        <div style={{ marginTop: 'var(--sp-lg)', padding: '12px 16px', borderRadius: 'var(--r-md)', background: 'rgba(59,130,246,0.08)', border: '1px solid rgba(59,130,246,0.2)', display: 'flex', alignItems: 'center', gap: 10 }}>
          <TrendingUp size={16} color="var(--clr-primary)" />
          <span style={{ fontSize: '0.82rem', color: 'var(--clr-text-secondary)' }}>
            Revenue grew <strong style={{ color: 'var(--clr-primary)' }}>+23.8%</strong> over the last 6 months, with April marking the highest month on record.
          </span>
        </div>
      </div>
    </Layout>
  );
}
