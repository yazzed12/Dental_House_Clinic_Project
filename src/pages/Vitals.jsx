import { useState, useEffect } from 'react';
import Layout from '../components/Layout';
import { Activity, Heart, Thermometer, Wind, Droplets, TrendingUp, TrendingDown } from 'lucide-react';

/* ── Animated Pulse Ring ─────────────────────────────────────── */
function PulseRing({ color }) {
  return (
    <div style={{ position: 'relative', width: 12, height: 12 }}>
      <div style={{ position: 'absolute', inset: 0, borderRadius: '50%', background: color, animation: 'pulse-glow 2s infinite' }} />
      <div style={{ width: '100%', height: '100%', borderRadius: '50%', background: color }} />
    </div>
  );
}

/* ── Vital Card ──────────────────────────────────────────────── */
function VitalCard({ icon: Icon, label, value, unit, normal, color, trend }) {
  const isNormal = trend === 'normal';
  return (
    <div className="stat-card" style={{ borderTop: `3px solid ${color}` }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 'var(--sp-md)' }}>
        <div style={{ width: 44, height: 44, borderRadius: 'var(--r-lg)', background: `${color}22`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon size={20} color={color} />
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
          <PulseRing color={isNormal ? '#10b981' : '#f59e0b'} />
          <span style={{ fontSize: '0.68rem', color: isNormal ? 'var(--clr-success)' : 'var(--clr-warning)', fontWeight: 700 }}>
            {isNormal ? 'Normal' : 'Watch'}
          </span>
        </div>
      </div>
      <div style={{ fontSize: '2rem', fontWeight: 800, color, lineHeight: 1 }}>{value}</div>
      <div style={{ fontSize: '0.75rem', color: 'var(--clr-text-muted)', marginTop: 2 }}>{unit}</div>
      <div style={{ fontSize: '0.78rem', fontWeight: 600, color: 'var(--clr-text-muted)', marginTop: 6 }}>{label}</div>
      <div style={{ fontSize: '0.7rem', color: 'var(--clr-text-muted)', marginTop: 3 }}>Normal: {normal}</div>
    </div>
  );
}

/* ── Mini Timeline ───────────────────────────────────────────── */
function Timeline({ data, color, height = 60 }) {
  const max = Math.max(...data);
  const min = Math.min(...data);
  const range = max - min || 1;
  const w = 100 / (data.length - 1);

  const points = data.map((v, i) => {
    const x = i * w;
    const y = height - ((v - min) / range) * (height - 8) - 4;
    return `${x},${y}`;
  }).join(' ');

  return (
    <svg width="100%" viewBox={`0 0 100 ${height}`} preserveAspectRatio="none" style={{ display: 'block' }}>
      <defs>
        <linearGradient id={`g-${color.replace('#','')}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.3" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <polygon
        points={`0,${height} ${points} 100,${height}`}
        fill={`url(#g-${color.replace('#','')})`}
      />
      <polyline points={points} fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/* ── Patient Vitals Table ────────────────────────────────────── */
const vitalsData = [
  { name: 'Eleanor Voss',   bp: '145/92', hr: 88,  temp: 37.1, spo2: 97, rr: 18, status: 'Stable'   },
  { name: 'Marcus Cole',    bp: '118/76', hr: 72,  temp: 36.8, spo2: 99, rr: 16, status: 'Normal'   },
  { name: 'Oliver Grant',   bp: '160/100',hr: 102, temp: 37.9, spo2: 94, rr: 22, status: 'Critical' },
  { name: 'Priya Sharma',   bp: '110/70', hr: 95,  temp: 37.4, spo2: 93, rr: 24, status: 'Watch'    },
  { name: 'Kwame Asante',   bp: '152/95', hr: 110, temp: 38.2, spo2: 91, rr: 26, status: 'Critical' },
  { name: 'Nina Johansson', bp: '124/80', hr: 80,  temp: 36.9, spo2: 98, rr: 17, status: 'Normal'   },
];

const STATUS_BADGE = {
  Normal:   'badge badge-success',
  Stable:   'badge badge-cyan',
  Watch:    'badge badge-warning',
  Critical: 'badge badge-danger',
};

export default function Vitals() {
  /* Simulated live HR value */
  const [hr, setHr] = useState(72);
  const [hrHistory] = useState([68, 71, 74, 70, 73, 75, 72, 74, 71, 72]);

  useEffect(() => {
    const id = setInterval(() => {
      setHr(prev => Math.max(60, Math.min(100, prev + Math.round((Math.random() - 0.5) * 6))));
    }, 2000);
    return () => clearInterval(id);
  }, []);

  return (
    <Layout pageTitle="Vitals Monitor" pageSubtitle="Real-time patient vital sign tracking">

      {/* ── Live Vitals Strip ── */}
      <div className="grid-4 stagger animate-fadeIn" style={{ marginBottom: 'var(--sp-xl)' }}>
        <VitalCard icon={Heart}       label="Heart Rate"     value={hr}     unit="bpm"   normal="60–100 bpm"   color="#ef4444" trend="normal" />
        <VitalCard icon={Activity}    label="Blood Pressure" value="124/80" unit="mmHg"  normal="<120/80 mmHg" color="#3b82f6" trend="normal" />
        <VitalCard icon={Thermometer} label="Temperature"    value="37.1"   unit="°C"    normal="36.1–37.2 °C" color="#f59e0b" trend="normal" />
        <VitalCard icon={Droplets}    label="SpO₂"           value="97%"    unit="oxygen saturation" normal="≥95%" color="#10b981" trend="normal" />
      </div>

      {/* ── Trend Chart ── */}
      <div className="grid-2 animate-fadeIn" style={{ marginBottom: 'var(--sp-xl)', animationDelay: '100ms' }}>
        <div className="card">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 'var(--sp-md)' }}>
            <div>
              <h3 style={{ fontSize: '0.95rem', fontWeight: 700 }}>Heart Rate Trend</h3>
              <p style={{ fontSize: '0.75rem', margin: 0 }}>Live · updating every 2s</p>
            </div>
            <span style={{ fontSize: '1.5rem', fontWeight: 800, color: '#ef4444' }}>{hr} <span style={{ fontSize: '0.7rem', color: 'var(--clr-text-muted)' }}>bpm</span></span>
          </div>
          <Timeline data={[...hrHistory.slice(-9), hr]} color="#ef4444" height={70} />
        </div>

        <div className="card">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 'var(--sp-md)' }}>
            <div>
              <h3 style={{ fontSize: '0.95rem', fontWeight: 700 }}>SpO₂ Trend</h3>
              <p style={{ fontSize: '0.75rem', margin: 0 }}>Last 10 readings</p>
            </div>
            <span style={{ fontSize: '1.5rem', fontWeight: 800, color: '#10b981' }}>97% <span style={{ fontSize: '0.7rem', color: 'var(--clr-text-muted)' }}>SpO₂</span></span>
          </div>
          <Timeline data={[96, 97, 95, 98, 97, 99, 97, 96, 98, 97]} color="#10b981" height={70} />
        </div>
      </div>

      {/* ── Patient Vitals Table ── */}
      <div className="card animate-fadeIn" style={{ padding: 0, overflow: 'hidden', animationDelay: '200ms' }}>
        <div style={{ padding: 'var(--sp-lg)', borderBottom: '1px solid var(--clr-border)' }}>
          <h3 style={{ fontSize: '1rem', fontWeight: 700 }}>All Patient Vitals</h3>
          <p style={{ fontSize: '0.78rem', margin: 0 }}>Last recorded readings</p>
        </div>
        <div className="table-wrapper" style={{ borderRadius: 0, border: 'none' }}>
          <table>
            <thead><tr>
              <th>Patient</th><th>Blood Pressure</th><th>Heart Rate</th>
              <th>Temp (°C)</th><th>SpO₂</th><th>Resp. Rate</th><th>Status</th>
            </tr></thead>
            <tbody>
              {vitalsData.map(v => (
                <tr key={v.name}>
                  <td style={{ fontWeight: 600, color: 'var(--clr-text-primary)' }}>{v.name}</td>
                  <td style={{ fontFamily: 'var(--font-mono)', color: parseInt(v.bp) > 140 ? 'var(--clr-warning)' : 'var(--clr-text-secondary)' }}>{v.bp}</td>
                  <td style={{ fontFamily: 'var(--font-mono)', color: v.hr > 100 ? 'var(--clr-danger)' : 'var(--clr-text-secondary)', fontWeight: v.hr > 100 ? 700 : 400 }}>
                    {v.hr} <span style={{ fontSize: '0.7rem', color: 'var(--clr-text-muted)' }}>bpm</span>
                  </td>
                  <td style={{ fontFamily: 'var(--font-mono)', color: v.temp > 37.5 ? 'var(--clr-warning)' : 'var(--clr-text-secondary)' }}>{v.temp}</td>
                  <td style={{ fontFamily: 'var(--font-mono)', color: v.spo2 < 95 ? 'var(--clr-danger)' : 'var(--clr-success)', fontWeight: 700 }}>{v.spo2}%</td>
                  <td style={{ fontFamily: 'var(--font-mono)', color: v.rr > 20 ? 'var(--clr-warning)' : 'var(--clr-text-secondary)' }}>{v.rr}/min</td>
                  <td><span className={STATUS_BADGE[v.status]}>{v.status}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </Layout>
  );
}
