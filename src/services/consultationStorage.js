/**
 * Consultation Storage Service
 * Handles persistence for clinical dental records.
 * Currently uses localStorage for persistence across page refreshes.
 */

const STORAGE_PREFIX = 'SDC_CONSULTATION_';

/**
 * Saves the entire consultation state for a patient.
 * @param {string} patientId 
 * @param {Object} toothData 
 */
export const saveConsultation = (patientId, toothData) => {
  if (!patientId) return;
  const data = {
    patientId,
    lastUpdated: new Date().toISOString(),
    toothData
  };
  localStorage.setItem(`${STORAGE_PREFIX}${patientId}`, JSON.stringify(data));
};

/**
 * Loads the consultation state for a patient.
 * @param {string} patientId 
 * @returns {Object|null}
 */
export const loadConsultation = (patientId) => {
  if (!patientId) return null;
  const data = localStorage.getItem(`${STORAGE_PREFIX}${patientId}`);
  try {
    return data ? JSON.parse(data) : null;
  } catch {
    console.error("Clinical data corruption detected for patient:", patientId);
    return null;
  }
};

/**
 * Clears the consultation record for a specific patient.
 */
export const clearConsultation = (patientId) => {
  if (!patientId) return;
  localStorage.removeItem(`${STORAGE_PREFIX}${patientId}`);
};

/**
 * Updates a single tooth record in the persistent storage.
 * @param {string} patientId 
 * @param {string} toothId 
 * @param {Object} record 
 */
export const updateToothRecord = (patientId, toothId, record) => {
  if (!patientId || !toothId) return;
  
  const existing = loadConsultation(patientId);
  const updatedToothData = existing ? { ...existing.toothData } : {};
  
  updatedToothData[toothId] = {
    ...updatedToothData[toothId],
    ...record,
    lastUpdated: new Date().toISOString()
  };

  saveConsultation(patientId, updatedToothData);
};

/**
 * Appends an entry to a tooth's history.
 * @param {string} patientId 
 * @param {string} toothId 
 * @param {Object} historyEntry 
 */
export const appendToothHistory = (patientId, toothId, historyEntry) => {
  if (!patientId || !toothId) return;
  
  const existing = loadConsultation(patientId);
  const toothRecord = existing?.toothData?.[toothId] || { history: [] };
  
  const updatedHistory = [
    ...(toothRecord.history || []),
    { ...historyEntry, date: new Date().toISOString() }
  ];

  updateToothRecord(patientId, toothId, { history: updatedHistory });
};
