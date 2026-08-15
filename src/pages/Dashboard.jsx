import Layout from '../components/Layout';
import {
  Users, Calendar, UserCheck, Bed, TrendingUp, TrendingDown,
  DollarSign, Activity, Clock, ChevronRight, AlertTriangle, CheckCircle
} from 'lucide-react';
import { appointments, doctors, weeklyAppointments, patientsByDept } from '../data/mockData';

// ── Mini Bar Chart ──────────────────────────────────────────────
function BarChart({ data }) {
  const max = Math.max(...data.map(d => d.count));
  return (
    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 8, height: 100 }}>
      {data.map(({ day, count }) => (
        <div key={day} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
          <div
            style={{
              width: '100%', borderRadius: 4,
              background: 'var(--grad-primary)',
              height: `${(count / max) * 84}px`,
              opacity: 0.85,
              transition: 'height 0.6s ease',
              boxShadow: '0 2px 10px rgba(59,130,246,0.25)',
            }}
            title={`${day}: ${count} appointments`}
          />
          <span style={{ fontSize: '0.65rem', color: 'var(--clr-text-muted)', fontWeight: 600 }}>{day}</span>
        </div>
      ))}
    </div>
  );
}

// ── Donut Chart ─────────────────────────────────────────────────
function DonutChart({ data }) {
  const total = data.reduce((s, d) => s + d.count, 0);
  const r = 48, cx = 60, cy = 60, strokeWidth = 14;
  const circumference = 2 * Math.PI * r;
  const segments = data.map((item, index) => {
    const previousTotal = data.slice(0, index).reduce((sum, d) => sum + d.count, 0);
    const fraction = item.count / total;
    return {
      ...item,
      dashArray: `${fraction * circumference} ${circumference}`,
      rotation: -90 + (previousTotal / total) * 360,
    };
  });

  return (
    <div style={{ display: 'flex', gap: 16, alignItems: 'center', flexWrap: 'wrap' }}>
      <svg width={120} height={120} viewBox="0 0 120 120" style={{ flexShrink: 0 }}>
        <circle cx={cx} cy={cy} r={r} fill="none" stroke="var(--clr-surface-2)" strokeWidth={strokeWidth} />
        {segments.map(({ dept, color, dashArray, rotation }) => {
          return (
            <circle
              key={dept}
              cx={cx} cy={cy} r={r}
              fill="none"
              stroke={color}
              strokeWidth={strokeWidth}
              strokeDasharray={dashArray}
              strokeDashoffset={0}
              strokeLinecap="butt"
              transform={`rotate(${rotation} ${cx} ${cy})`}
            />
          );
        })}
        <text x={cx} y={cy - 5} textAnchor="middle" fill="var(--clr-text-primary)" fontSize="13" fontWeight="800">{total}</text>
        <text x={cx} y={cy + 10} textAnchor="middle" fill="var(--clr-text-muted)" fontSize="7">PATIENTS</text>
      </svg>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 0 }}>
        {data.map(({ dept, count, color }) => (
          <div key={dept} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ width: 9, height: 9, borderRadius: '50%', background: color, flexShrink: 0 }} />
            <span style={{ fontSize: '0.75rem', color: 'var(--clr-text-muted)', flex: 1 }}>{dept}</span>
            <span style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--clr-text-primary)' }}>{count}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Stat Card ───────────────────────────────────────────────────
function StatCard({ icon: Icon, label, value, change, color, accent }) {
  const up = change >= 0;
  return (
    <div className={`stat-card ${accent}`}>
      <div className="stat-icon" style={{ background: `${color}22` }}>
        <Icon size={22} color={color} strokeWidth={2} />
      </div>
      <div className="stat-value" style={{ background: `linear-gradient(90deg, ${color}, #fff)`, WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent', backgroundClip: 'text' }}>
        {value}
      </div>
      <div className="stat-label">{label}</div>
      {change !== 0 && (
        <div className={`stat-change ${up ? 'up' : 'down'}`}>
          {up ? <TrendingUp size={12} /> : <TrendingDown size={12} />}
          {' '}{Math.abs(change)}% vs last month
        </div>
      )}
    </div>
  );
}

// ── Status Badge ────────────────────────────────────────────────
function StatusBadge({ status }) {
  const map = {
    Confirmed: 'badge badge-success',
    Pending:   'badge badge-warning',
    Cancelled: 'badge badge-danger',
    Urgent:    'badge badge-danger',
  };
  return <span className={map[status] || 'badge badge-primary'}>{status}</span>;
}

// ── Dashboard Page ───────────────────────────────────────────────
export default function Dashboard() {
  const todayAppts = appointments.slice(0, 5);
  const onlineDoctors = doctors.filter(d => d.status === 'online');

  return (
    <Layout pageTitle="Dashboard" pageSubtitle="Welcome back, Admin · Tuesday, 22 April 2026">
      {/* ── KPI Grid ── */}
      <div className="grid-4 stagger animate-fadeIn" style={{ marginBottom: 'var(--sp-xl)' }}>
        <StatCard icon={Users}       label="Total Patients"        value="1,248" change={12}  color="#3b82f6" accent="primary" />
        <StatCard icon={Calendar}    label="Today's Appointments"  value="34"    change={5}   color="#10b981" accent="success" />
        <StatCard icon={UserCheck}   label="Active Doctors"        value="18"    change={0}   color="#8b5cf6" accent="purple" />
        <StatCard icon={DollarSign}  label="Monthly Revenue"       value="$84.2K" change={8}  color="#f59e0b" accent="warning" />
      </div>

      {/* ── Row 2: Charts ── */}
      <div className="grid-2 animate-fadeIn" style={{ marginBottom: 'var(--sp-xl)', animationDelay: '100ms' }}>
        {/* Weekly Appointments */}
        <div className="card">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 'var(--sp-lg)' }}>
            <div>
              <h3 style={{ fontSize: '1rem', fontWeight: 700 }}>Weekly Appointments</h3>
              <p style={{ fontSize: '0.78rem', color: 'var(--clr-text-muted)', margin: 0 }}>295 total this week</p>
            </div>
            <span className="badge badge-primary">
              <Activity size={10} /> Live
            </span>
          </div>
          <BarChart data={weeklyAppointments} />
        </div>

        {/* Patients by Dept */}
        <div className="card">
          <div style={{ marginBottom: 'var(--sp-lg)' }}>
            <h3 style={{ fontSize: '1rem', fontWeight: 700 }}>Patients by Department</h3>
            <p style={{ fontSize: '0.78rem', color: 'var(--clr-text-muted)', margin: 0 }}>Distribution across specialties</p>
          </div>
          <DonutChart data={patientsByDept} />
        </div>
      </div>

      {/* ── Row 3: Appointments + Doctors ── */}
      <div className="grid-2 animate-fadeIn" style={{ animationDelay: '200ms' }}>
        {/* Upcoming Appointments */}
        <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: 'var(--sp-lg)' }}>
            <h3 style={{ fontSize: '1rem', fontWeight: 700 }}>Today's Appointments</h3>
            <a href="/appointments" style={{ fontSize: '0.78rem', display: 'flex', alignItems: 'center', gap: 4, color: 'var(--clr-primary)', fontWeight: 600 }}>
              View all <ChevronRight size={14} />
            </a>
          </div>
          <div className="table-wrapper" style={{ borderRadius: 0, border: 'none' }}>
            <table>
              <thead>
                <tr>
                  <th>Patient</th>
                  <th>Doctor</th>
                  <th>Time</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {todayAppts.map(a => (
                  <tr key={a.id}>
                    <td style={{ fontWeight: 600, color: 'var(--clr-text-primary)' }}>{a.patient}</td>
                    <td>{a.doctor.replace('Dr. ', 'Dr. ')}</td>
                    <td>
                      <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                        <Clock size={12} style={{ color: 'var(--clr-text-muted)' }} /> {a.time}
                      </span>
                    </td>
                    <td><StatusBadge status={a.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Online Doctors */}
        <div className="card">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 'var(--sp-lg)' }}>
            <h3 style={{ fontSize: '1rem', fontWeight: 700 }}>Doctors On Duty</h3>
            <span className="badge badge-success">
              <span style={{ width: 6, height: 6, background: 'var(--clr-success)', borderRadius: '50%' }} />
              {onlineDoctors.length} Online
            </span>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--sp-md)' }}>
            {onlineDoctors.map(doc => (
              <div key={doc.id} style={{
                display: 'flex', alignItems: 'center', gap: 12,
                padding: '10px 14px', borderRadius: 'var(--r-md)',
                background: 'var(--clr-surface-2)', border: '1px solid var(--clr-border)',
                transition: 'all var(--tr-fast)',
              }}
              onMouseEnter={e => { e.currentTarget.style.borderColor = 'var(--clr-border-2)'; e.currentTarget.style.transform = 'translateX(3px)'; }}
              onMouseLeave={e => { e.currentTarget.style.borderColor = 'var(--clr-border)'; e.currentTarget.style.transform = 'translateX(0)'; }}
              >
                <div className="avatar-wrap">
                  <div className="avatar" style={{ background: `linear-gradient(135deg, ${doc.color}, ${doc.color}aa)`, width: 38, height: 38, fontSize: '0.75rem' }}>
                    {doc.avatar}
                  </div>
                  <span className={`status-dot ${doc.status}`} />
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--clr-text-primary)' }}>{doc.name}</div>
                  <div style={{ fontSize: '0.72rem', color: 'var(--clr-text-muted)' }}>{doc.specialty}</div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div style={{ fontSize: '0.8rem', fontWeight: 700, color: doc.color }}>{doc.patients}</div>
                  <div style={{ fontSize: '0.65rem', color: 'var(--clr-text-muted)' }}>patients</div>
                </div>
              </div>
            ))}
          </div>

          {/* Quick Alerts */}
          <div style={{ marginTop: 'var(--sp-lg)', padding: '10px 14px', borderRadius: 'var(--r-md)', background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.2)', display: 'flex', alignItems: 'flex-start', gap: 10 }}>
            <AlertTriangle size={16} color="var(--clr-danger)" style={{ flexShrink: 0, marginTop: 2 }} />
            <div>
              <div style={{ fontSize: '0.8rem', fontWeight: 600, color: '#f87171' }}>Critical Alert</div>
              <div style={{ fontSize: '0.75rem', color: 'var(--clr-text-muted)' }}>Patient Oliver Grant needs urgent attention — Room C-305</div>
            </div>
          </div>
        </div>
      </div>
    </Layout>
  );
}
