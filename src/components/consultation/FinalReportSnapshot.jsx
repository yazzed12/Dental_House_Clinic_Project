import React from 'react';
import MedicalReportMarkdown from './MedicalReportMarkdown.jsx';

export default function FinalReportSnapshot({ snapshot }) {
  const finalNarrative = snapshot?.finalNarrative;
  if (!finalNarrative) return null;

  // Migration 020 stores the approved Markdown verbatim. History must render
  // that immutable narrative directly, without rebuilding or rewriting it.
  return <MedicalReportMarkdown markdown={finalNarrative} />;
}
