export const TOOTH_TYPES = {
  INCISOR: 'Incisor',
  CANINE: 'Canine',
  PREMOLAR: 'Premolar',
  MOLAR: 'Molar'
};

export const TOOTH_STATUS = {
  HEALTHY: 'healthy',
  PROBLEM: 'problem',
  TREATED: 'treated',
  MISSING: 'missing'
};

// Source of truth for FDI Tooth Mapping (ISO 3950)
export const FDI_TOOTH_MAP = {
  // Quadrant 1: Upper Right (11-18)
  "11": { id: "11", fdi: 11, name: "Upper Right Central Incisor", arch: "upper", quadrant: 1, type: TOOTH_TYPES.INCISOR },
  "12": { id: "12", fdi: 12, name: "Upper Right Lateral Incisor", arch: "upper", quadrant: 1, type: TOOTH_TYPES.INCISOR },
  "13": { id: "13", fdi: 13, name: "Upper Right Canine", arch: "upper", quadrant: 1, type: TOOTH_TYPES.CANINE },
  "14": { id: "14", fdi: 14, name: "Upper Right First Premolar", arch: "upper", quadrant: 1, type: TOOTH_TYPES.PREMOLAR },
  "15": { id: "15", fdi: 15, name: "Upper Right Second Premolar", arch: "upper", quadrant: 1, type: TOOTH_TYPES.PREMOLAR },
  "16": { id: "16", fdi: 16, name: "Upper Right First Molar", arch: "upper", quadrant: 1, type: TOOTH_TYPES.MOLAR },
  "17": { id: "17", fdi: 17, name: "Upper Right Second Molar", arch: "upper", quadrant: 1, type: TOOTH_TYPES.MOLAR },
  "18": { id: "18", fdi: 18, name: "Upper Right Third Molar", arch: "upper", quadrant: 1, type: TOOTH_TYPES.MOLAR },

  // Quadrant 2: Upper Left (21-28)
  "21": { id: "21", fdi: 21, name: "Upper Left Central Incisor", arch: "upper", quadrant: 2, type: TOOTH_TYPES.INCISOR },
  "22": { id: "22", fdi: 22, name: "Upper Left Lateral Incisor", arch: "upper", quadrant: 2, type: TOOTH_TYPES.INCISOR },
  "23": { id: "23", fdi: 23, name: "Upper Left Canine", arch: "upper", quadrant: 2, type: TOOTH_TYPES.CANINE },
  "24": { id: "24", fdi: 24, name: "Upper Left First Premolar", arch: "upper", quadrant: 2, type: TOOTH_TYPES.PREMOLAR },
  "25": { id: "25", fdi: 25, name: "Upper Left Second Premolar", arch: "upper", quadrant: 2, type: TOOTH_TYPES.PREMOLAR },
  "26": { id: "26", fdi: 26, name: "Upper Left First Molar", arch: "upper", quadrant: 2, type: TOOTH_TYPES.MOLAR },
  "27": { id: "27", fdi: 27, name: "Upper Left Second Molar", arch: "upper", quadrant: 2, type: TOOTH_TYPES.MOLAR },
  "28": { id: "28", fdi: 28, name: "Upper Left Third Molar", arch: "upper", quadrant: 2, type: TOOTH_TYPES.MOLAR },

  // Quadrant 3: Lower Left (31-38)
  "31": { id: "31", fdi: 31, name: "Lower Left Central Incisor", arch: "lower", quadrant: 3, type: TOOTH_TYPES.INCISOR },
  "32": { id: "32", fdi: 32, name: "Lower Left Lateral Incisor", arch: "lower", quadrant: 3, type: TOOTH_TYPES.INCISOR },
  "33": { id: "33", fdi: 33, name: "Lower Left Canine", arch: "lower", quadrant: 3, type: TOOTH_TYPES.CANINE },
  "34": { id: "34", fdi: 34, name: "Lower Left First Premolar", arch: "lower", quadrant: 3, type: TOOTH_TYPES.PREMOLAR },
  "35": { id: "35", fdi: 35, name: "Lower Left Second Premolar", arch: "lower", quadrant: 3, type: TOOTH_TYPES.PREMOLAR },
  "36": { id: "36", fdi: 36, name: "Lower Left First Molar", arch: "lower", quadrant: 3, type: TOOTH_TYPES.MOLAR },
  "37": { id: "37", fdi: 37, name: "Lower Left Second Molar", arch: "lower", quadrant: 3, type: TOOTH_TYPES.MOLAR },
  "38": { id: "38", fdi: 38, name: "Lower Left Third Molar", arch: "lower", quadrant: 3, type: TOOTH_TYPES.MOLAR },

  // Quadrant 4: Lower Right (41-48)
  "41": { id: "41", fdi: 41, name: "Lower Right Central Incisor", arch: "lower", quadrant: 4, type: TOOTH_TYPES.INCISOR },
  "42": { id: "42", fdi: 42, name: "Lower Right Lateral Incisor", arch: "lower", quadrant: 4, type: TOOTH_TYPES.INCISOR },
  "43": { id: "43", fdi: 43, name: "Lower Right Canine", arch: "lower", quadrant: 4, type: TOOTH_TYPES.CANINE },
  "44": { id: "44", fdi: 44, name: "Lower Right First Premolar", arch: "lower", quadrant: 4, type: TOOTH_TYPES.PREMOLAR },
  "45": { id: "45", fdi: 45, name: "Lower Right Second Premolar", arch: "lower", quadrant: 4, type: TOOTH_TYPES.PREMOLAR },
  "46": { id: "46", fdi: 46, name: "Lower Right First Molar", arch: "lower", quadrant: 4, type: TOOTH_TYPES.MOLAR },
  "47": { id: "47", fdi: 47, name: "Lower Right Second Molar", arch: "lower", quadrant: 4, type: TOOTH_TYPES.MOLAR },
  "48": { id: "48", fdi: 48, name: "Lower Right Third Molar", arch: "lower", quadrant: 4, type: TOOTH_TYPES.MOLAR },
};

export const getToothById = (id) => FDI_TOOTH_MAP[id?.toString()];

export const INITIAL_CLINICAL_STATE = Object.keys(FDI_TOOTH_MAP).reduce((acc, key) => {
  acc[key] = {
    status: TOOTH_STATUS.HEALTHY,
    notes: '',
    history: [],
    conditions: [],
    treatments: []
  };
  return acc;
}, {});
