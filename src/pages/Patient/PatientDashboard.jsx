import React from 'react';
import { ShieldAlert } from 'lucide-react';
import Layout from '../../components/Layout';

export default function PatientDashboard() {
  return (
    <Layout pageTitle="Patient Portal" pageSubtitle="Secure patient access">
      <div className="page-stack animate-fadeIn">
        <section className="card" style={{ textAlign: 'center', padding: '48px 24px' }}>
          <ShieldAlert size={38} color="var(--clr-warning)" style={{ marginBottom: 14 }} />
          <h2 className="section-title">Patient portal is not available yet</h2>
          <p className="section-subtitle" style={{ maxWidth: 520, margin: '8px auto 0' }}>
            Trusted patient identity and access controls are still being prepared. No clinical, appointment, or report data is displayed until secure access is available.
          </p>
        </section>
      </div>
    </Layout>
  );
}
