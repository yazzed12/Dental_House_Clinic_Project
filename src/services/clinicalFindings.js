const asToothId = value => String(value ?? '');

export const normalizeFinding = finding => ({
  toothId: asToothId(finding.toothId),
  toothStatus: String(finding.toothStatus ?? ''),
  symptoms: Array.isArray(finding.symptoms) ? [...finding.symptoms] : [],
  toothNote: String(finding.toothNote ?? ''),
});

export const hydrateClinicalFindings = snapshot => {
  if (!Array.isArray(snapshot)) return null;
  return snapshot.reduce((result, finding) => {
    const normalized = normalizeFinding(finding);
    if (normalized.toothId) result[normalized.toothId] = normalized;
    return result;
  }, {});
};

export const serializeClinicalFindings = findingsByTooth => (
  Object.values(findingsByTooth || {})
    .map(normalizeFinding)
    .sort((left, right) => Number(left.toothId) - Number(right.toothId))
);

export const upsertClinicalFinding = (findingsByTooth, toothId, toothRecord, updates = {}) => {
  const id = asToothId(toothId);
  const current = findingsByTooth?.[id];
  return {
    ...(findingsByTooth || {}),
    [id]: normalizeFinding({
      toothId: id,
      toothStatus: updates.toothStatus ?? toothRecord?.status ?? current?.toothStatus ?? 'healthy',
      symptoms: updates.symptoms ?? current?.symptoms ?? [],
      toothNote: updates.toothNote ?? toothRecord?.notes ?? current?.toothNote ?? '',
    }),
  };
};

export const removeClinicalFinding = (findingsByTooth, toothId) => {
  const next = { ...(findingsByTooth || {}) };
  delete next[asToothId(toothId)];
  return next;
};

export const unionFindingSymptoms = findingsByTooth => {
  const symptoms = new Map();
  serializeClinicalFindings(findingsByTooth).forEach(finding => {
    finding.symptoms.forEach(value => {
      const clean = String(value).trim();
      const key = clean.toLowerCase();
      if (clean && !symptoms.has(key)) symptoms.set(key, clean);
    });
  });
  return [...symptoms.values()].sort((a, b) => (
    a.localeCompare(b, undefined, { sensitivity: 'base' }) || a.localeCompare(b)
  ));
};
