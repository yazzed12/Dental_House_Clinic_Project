import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

test('history Lab snapshots stay outside Medical Report renderers and make no catalog calls', async () => {
  const page = await readFile(new URL('../pages/Doctor/ConsultationsHistory.jsx', import.meta.url), 'utf8');
  const section = await readFile(new URL('../components/consultation/ConsultationLabHistorySection.jsx', import.meta.url), 'utf8');
  const service = await readFile(new URL('./consultationHistoryApi.js', import.meta.url), 'utf8');
  assert.match(page, /<ConsultationLabHistorySection labItems=\{report\.labItems\} labNote=\{report\.labNote\} \/>/);
  assert.doesNotMatch(section, /MedicalReportMarkdown|FinalReportSnapshot|reportSnapshot|finalNarrative/);
  assert.doesNotMatch(service, /list_labs|list_lab_products|get_consultation_lab_items|\.from\(/);
  assert.doesNotMatch(page, /MedicalReportMarkdown[^>]*(labItems|labNote)|(labItems|labNote)[^<]*MedicalReportMarkdown/);
});
