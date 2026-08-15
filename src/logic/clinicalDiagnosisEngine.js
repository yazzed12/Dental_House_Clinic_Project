import { KNOWLEDGE_BASE } from '../data/medicalKnowledge';

export const generateClinicalReport = (selectedSymptoms, toothId, patient) => {
  // 1. Calculate matching score for each knowledge base entry
  let bestMatch = null;
  let maxScore = -1;

  for (const entry of KNOWLEDGE_BASE) {
    let score = 0;
    // Count how many symptoms match
    for (const condition of entry.conditions) {
      if (selectedSymptoms.includes(condition)) {
        score += 1;
      }
    }
    
    // Penalize if there are symptoms not in the condition list? 
    // Or just take the one with the highest absolute match.
    // Let's use simple highest overlap:
    if (score > maxScore && score > 0) {
      maxScore = score;
      bestMatch = entry;
    }
  }

  // 2. Default fallback if no matches
  if (!bestMatch) {
    return {
      findings: "Patient presents with non-specific symptoms. Clinical examination required.",
      diagnosis: "Undetermined / Pending Clinical Exam",
      treatment: "Comprehensive Examination & Radiographs",
      urgency: "Low",
      snomed: "N/A"
    };
  }

  // 3. Format the report
  const findings = `Tooth #${toothId || 'Unknown'}: ${bestMatch.template}`;
  
  return {
    findings,
    diagnosis: bestMatch.diagnosis,
    treatment: bestMatch.treatment,
    urgency: bestMatch.urgency,
    snomed: bestMatch.snomed
  };
};
