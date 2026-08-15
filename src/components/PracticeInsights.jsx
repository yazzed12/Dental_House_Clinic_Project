import React, { useMemo } from 'react';
import {
  Sparkles, TrendingUp, Users, Calendar,
  CheckCircle2, Clock, Stethoscope, FileText
} from 'lucide-react';
import { useData } from '../context/DataContext';

export default function PracticeInsights() {
  const { appointments, patients, records } = useData();

  const todayStr = new Date().toISOString().split('T')[0];

  const stats = useMemo(() => {
    const todayAppts = appointments.filter(a => a.date === todayStr);
    const completed = todayAppts.filter(a => a.status === 'Completed').length;
    const pending = todayAppts.filter(a => a.status !== 'Completed').length;
    const total = todayAppts.length;
    const completionRate = total > 0 ? Math.round((completed / total) * 100) : 0;

    // Upcoming types breakdown
    const types = {};
    todayAppts.filter(a => a.status !== 'Completed').forEach(a => {
      const t = a.type || 'General';
      types[t] = (types[t] || 0) + 1;
    });
    const topTypes = Object.entries(types).sort((a, b) => b[1] - a[1]).slice(0, 3);

    return { completed, pending, total, completionRate, topTypes, totalPatients: patients.length, totalRecords: records.length };
  }, [appointments, patients, records, todayStr]);

  const metrics = [
    { label: 'Total Patients', value: stats.totalPatients, icon: Users, color: '#6366f1' },
    { label: 'Today Sessions', value: stats.total, icon: Calendar, color: '#ec4899' },
    { label: 'Completed', value: stats.completed, icon: CheckCircle2, color: '#10b981' },
    { label: 'Pending', value: stats.pending, icon: Clock, color: '#f59e0b' },
  ];

  // Generate actionable insights based on real data
  const insights = useMemo(() => {
    const list = [];
    if (stats.pending > 0) {
      list.push(`${stats.pending} consultation${stats.pending > 1 ? 's' : ''} remaining for today.`);
    }
    if (stats.completed > 0 && stats.pending === 0) {
      list.push('All consultations for today are complete. Great work!');
    }
    if (stats.total === 0) {
      list.push('No appointments scheduled for today. Consider reviewing pending records.');
    }
    if (stats.topTypes.length > 0) {
      const typesStr = stats.topTypes.map(([t, c]) => `${t} (${c})`).join(', ');
      list.push(`Today's appointment types: ${typesStr}`);
    }
    if (stats.totalRecords > 0) {
      list.push(`${stats.totalRecords} active clinical record${stats.totalRecords > 1 ? 's' : ''} in the system.`);
    }
    if (list.length === 0) {
      list.push('Clinic is operating normally. Continue monitoring your schedule.');
    }
    return list;
  }, [stats]);

  return (
    <div className="card" style={{ position: 'relative', overflow: 'hidden' }}>
      {/* Subtle background decoration */}
      <Sparkles size={100} style={{ position: 'absolute', top: -16, right: -16, opacity: 0.03, color: 'var(--clr-primary)' }} />

      <div className="section-header" style={{ marginBottom: 16 }}>
        <div>
          <p className="section-kicker" style={{ color: 'var(--clr-primary)', display: 'flex', alignItems: 'center', gap: 4 }}>
            <Sparkles size={12} /> Today's Summary
          </p>
          <h3 className="section-title">Practice Overview</h3>
        </div>
        {stats.total > 0 && (
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8,
            padding: '6px 14px', borderRadius: 999,
            background: stats.completionRate === 100 ? 'var(--clr-primary-light)' : 'rgba(245, 158, 11, 0.1)',
            color: stats.completionRate === 100 ? 'var(--clr-primary-dark)' : '#b45309',
            fontSize: '0.78rem', fontWeight: 800,
          }}>
            <TrendingUp size={14} />
            {stats.completionRate}% complete
          </div>
        )}
      </div>

      {/* Metric Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(130px, 1fr))', gap: 10, marginBottom: 18 }}>
        {metrics.map((m) => (
          <div key={m.label} style={{
            padding: 12,
            background: 'var(--clr-bg)',
            border: '1px solid var(--clr-border)',
            borderRadius: 10,
            display: 'flex', alignItems: 'center', gap: 10,
          }}>
            <div style={{
              width: 32, height: 32, borderRadius: 8,
              background: `${m.color}15`,
              display: 'grid', placeItems: 'center',
            }}>
              <m.icon size={16} color={m.color} />
            </div>
            <div>
              <div style={{ fontSize: '0.68rem', color: 'var(--clr-subtext)', textTransform: 'uppercase', fontWeight: 800, letterSpacing: '0.02em' }}>
                {m.label}
              </div>
              <div style={{ fontSize: '1.1rem', fontWeight: 900, color: 'var(--clr-text)' }}>
                {m.value}
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Insights */}
      <div>
        <h4 style={{ fontSize: '0.84rem', fontWeight: 800, marginBottom: 10, display: 'flex', alignItems: 'center', gap: 6, color: 'var(--clr-text)' }}>
          <Stethoscope size={14} color="var(--clr-primary)" /> Clinical Insights
        </h4>
        <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 6 }}>
          {insights.map((insight, i) => (
            <li key={i} style={{
              display: 'flex', gap: 10, fontSize: '0.84rem',
              color: 'var(--clr-subtext)',
              padding: '10px 12px', borderRadius: 8,
              background: 'var(--clr-bg)',
              borderLeft: '3px solid var(--clr-primary)',
            }}>
              <span style={{ color: 'var(--clr-primary)', fontWeight: 'bold' }}>•</span>
              {insight}
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
