const text = value => typeof value === 'string' && value.trim() ? value.trim() : null;

export function serializeReviewedAssessments(findings, state) {
  return (findings || []).map(finding => {
    const reviewed = state?.[finding.toothId] || {};
    const icd = reviewed.icd10;
    return {
      toothId: String(finding.toothId),
      clinicalDescription: text(reviewed.clinicalDescription),
      diagnosis: text(reviewed.diagnosis),
      icd10: text(icd?.code) && text(icd?.display) ? { code: text(icd.code), display: text(icd.display) } : null,
      treatmentPlan: text(reviewed.treatmentPlan),
    };
  });
}
