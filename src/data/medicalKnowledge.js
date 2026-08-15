export const DENTAL_SYMPTOMS = [
  { id: 'sym-cold', label: 'Cold Sensitivity', category: 'Sensitivity', type: 'sensory' },
  { id: 'sym-hot', label: 'Hot Sensitivity', category: 'Sensitivity', type: 'sensory' },
  { id: 'sym-sweet', label: 'Sweet Sensitivity', category: 'Sensitivity', type: 'sensory' },
  { id: 'sym-sharp-pain', label: 'Sharp Pain', category: 'Pain', type: 'sensory' },
  { id: 'sym-dull-ache', label: 'Dull Ache', category: 'Pain', type: 'sensory' },
  { id: 'sym-spontaneous', label: 'Spontaneous Pain', category: 'Pain', type: 'sensory' },
  { id: 'sym-biting', label: 'Pain on Biting', category: 'Pain', type: 'sensory' },
  { id: 'sym-swelling', label: 'Swelling', category: 'Inflammation', type: 'visual' },
  { id: 'sym-bleeding', label: 'Bleeding Gums', category: 'Periodontal', type: 'visual' },
  { id: 'sym-mobility', label: 'Tooth Mobility', category: 'Structural', type: 'physical' },
  { id: 'sym-decay', label: 'Visible Decay', category: 'Caries', type: 'visual' },
  { id: 'sym-fracture', label: 'Fractured/Chipped', category: 'Structural', type: 'visual' },
  { id: 'sym-filling-issue', label: 'Defective Restoration', category: 'Restoration', type: 'visual' },
  { id: 'sym-halitosis', label: 'Halitosis (Bad Breath)', category: 'General', type: 'sensory' }
];

export const KNOWLEDGE_BASE = [
  {
    conditions: ['sym-spontaneous', 'sym-hot', 'sym-swelling'],
    diagnosis: 'Acute Irreversible Pulpitis with Apical Periodontitis (K04.0)',
    snomed: '23456789',
    treatment: 'Root Canal Therapy (RCT) or Extraction',
    urgency: 'High - Immediate attention required',
    template: 'Patient presents with severe spontaneous pain and thermal sensitivity lingering after stimulus removal, accompanied by localized swelling. Clinical findings are consistent with acute irreversible pulpitis and symptomatic apical periodontitis. Immediate endodontic intervention is recommended.'
  },
  {
    conditions: ['sym-decay', 'sym-sweet', 'sym-cold'],
    diagnosis: 'Dental Caries into Dentin (K02.1)',
    snomed: '80816005',
    treatment: 'Composite Restoration',
    urgency: 'Medium - Schedule within 2 weeks',
    template: 'Clinical examination reveals visible cavitation with reported sensitivity to cold and sweet stimuli. Pain is not spontaneous. Findings suggest active dentinal caries without irreversible pulpal involvement. Caries excavation and composite restoration are indicated.'
  },
  {
    conditions: ['sym-bleeding', 'sym-halitosis'],
    diagnosis: 'Gingivitis / Mild Periodontitis (K05.1)',
    snomed: '68566005',
    treatment: 'Scaling and Root Planing (SRP), Oral Hygiene Instruction',
    urgency: 'Low - Routine scheduling',
    template: 'Patient reports gingival bleeding and halitosis. Clinical visual signs point to plaque-induced gingival inflammation. Non-surgical periodontal therapy (scaling and polishing) with rigorous home care instruction is recommended.'
  },
  {
    conditions: ['sym-fracture', 'sym-sharp-pain', 'sym-biting'],
    diagnosis: 'Cracked Tooth Syndrome / Fractured Crown (S02.5)',
    snomed: '210964005',
    treatment: 'Full Coverage Crown or Extraction depending on fracture depth',
    urgency: 'High - Risk of pulpal exposure',
    template: 'Tooth presents with structural compromise and sharp pain elicited specifically upon mastication. Findings are indicative of a cracked tooth or fractured cusp. Immediate evaluation for cuspal coverage restoration is required to prevent catastrophic failure.'
  },
  {
    conditions: ['sym-mobility', 'sym-bleeding'],
    diagnosis: 'Advanced Periodontitis (K05.3)',
    snomed: '416608005',
    treatment: 'Deep Periodontal Therapy, Possible Splinting or Extraction',
    urgency: 'High - Risk of tooth loss',
    template: 'Significant tooth mobility accompanied by gingival bleeding points to severe loss of periodontal attachment. Comprehensive periodontal evaluation and aggressive intervention are necessary.'
  },
  {
    conditions: ['sym-cold'],
    diagnosis: 'Dentin Hypersensitivity (K03.8)',
    snomed: '74338006',
    treatment: 'Application of Desensitizing Agent, Fluoride Varnish',
    urgency: 'Low',
    template: 'Patient reports transient, sharp pain localized to cold stimuli without evidence of structural decay. Findings suggest dentin hypersensitivity likely due to gingival recession or enamel wear. Topical desensitization therapy is recommended.'
  },
  {
    conditions: ['sym-filling-issue', 'sym-cold', 'sym-sweet'],
    diagnosis: 'Secondary Caries / Defective Restoration (K02.8)',
    snomed: '59469007',
    treatment: 'Replacement of Defective Restoration',
    urgency: 'Medium',
    template: 'Existing restoration shows signs of marginal failure with recurrent decay, eliciting mild thermal sensitivity. Removal of the defective restoration, caries excavation, and placement of a new direct restoration are indicated.'
  }
];
