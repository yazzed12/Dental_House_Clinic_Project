/**
 * Centralized Clinical Data Options
 * Ensures consistency across the diagnostic engine and UI.
 */

export const CLINICAL_DIAGNOSES = [
  'Healthy / No issue',
  'Dental Caries',
  'Acute Pulpitis',
  'Gingivitis',
  'Periodontitis',
  'Tooth Sensitivity',
  'Enamel Erosion',
  'Cracked Tooth',
  'Periapical Abscess'
];

export const CLINICAL_TREATMENTS = [
  'No treatment needed',
  'Composite Filling',
  'Root Canal Treatment',
  'Scaling & Polishing',
  'Tooth Extraction',
  'Dental Crown',
  'Fluoride Application',
  'Deep Cleaning (SRP)',
  'Desensitizing Agent'
];

export const CLINICAL_SYMPTOMS = [
  { id: 'pain', label: 'Pain', levels: ['none', 'low', 'high'] },
  { id: 'sensitivity', label: 'Sensitivity', type: 'checkbox' },
  { id: 'bleeding', label: 'Bleeding Gums', type: 'checkbox' },
  { id: 'swelling', label: 'Swelling', type: 'checkbox' },
  { id: 'badBreath', label: 'Bad Breath', type: 'checkbox' },
  { id: 'previousFilling', label: 'Existing Filling', type: 'checkbox' },
  { id: 'mobility', label: 'Mobility', type: 'checkbox' }
];

export const CLINICAL_STATUSES = [
  { id: 'healthy', label: 'Healthy', color: '#22C55E' },
  { id: 'problem', label: 'Problem', color: '#EF4444' },
  { id: 'treated', label: 'Treated', color: '#3B82F6' },
  { id: 'missing', label: 'Missing', color: '#64748B' }
];
