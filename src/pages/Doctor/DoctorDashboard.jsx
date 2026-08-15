import React, { useState, useEffect } from 'react';
import { Clock } from 'lucide-react';
import Layout from '../../components/Layout';
import UpcomingConsultations from '../../components/UpcomingConsultations';
import PracticeInsights from '../../components/PracticeInsights';
import { useLanguage } from '../../context/LanguageContext';
import { getAuditLogs } from '../../services/dashboardApi.js';

export default function DoctorDashboard() {
  const { formatDateTime } = useLanguage();
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchLogs = async () => {
      try {
        setLoading(true);
        const logsData = await getAuditLogs();
        setLogs(logsData);
      } catch (err) {
        console.error('Dashboard fetch error:', err);
      } finally {
        setLoading(false);
      }
    };

    fetchLogs();
  }, []);

  return (
    <Layout pageTitle="Clinical Overview" pageSubtitle="Today schedule, patient queue, and clinical activity.">
      <div className="page-stack animate-fadeIn">

        {/* ── Practice Summary (Data-Driven) ─────────────────────────── */}
        <section>
          <PracticeInsights />
        </section>

        {/* ── Main Content Grid ─────────────────────────────────────────── */}
        <section className="content-grid-2">

          {/* Today's Consultations */}
          <UpcomingConsultations />

          {/* Right Column */}
          <div className="page-stack">



            {/* Recent Clinical Logs */}
            <div className="card">
              <h3 className="section-title" style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <Clock size={16} color="var(--clr-primary)" />
                Recent Clinical Logs
              </h3>
              <div className="page-stack" style={{ gap: 12, marginTop: 14 }}>
                {loading ? (
                  <div style={{ opacity: 0.4, fontSize: '0.86rem' }}>Loading logs…</div>
                ) : logs.length === 0 ? (
                  <div style={{ color: 'var(--clr-subtext)', fontSize: '0.86rem' }}>No logs available.</div>
                ) : (
                  logs.map((log) => (
                    <div className="row-actions" key={log.id} style={{ alignItems: 'flex-start' }}>
                      <div className="stat-icon" style={{ width: 34, height: 34 }}>
                        <Clock size={16} />
                      </div>
                      <div>
                        <strong style={{ fontSize: '0.86rem' }}>{log.message}</strong>
                        <div className="muted" style={{ fontSize: '0.76rem' }}>{formatDateTime(log.created_at, 'compact')}</div>
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>

          </div>
        </section>
      </div>
    </Layout>
  );
}
