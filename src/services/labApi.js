import { getSupabaseClient } from '../lib/supabaseClient.js';

export class LabApiError extends Error {
  constructor(message, { code = 'LAB_RPC_FAILED', kind = 'transport', status, cause } = {}) {
    super(message, { cause });
    this.name = 'LabApiError';
    this.code = code;
    this.kind = kind;
    if (status !== undefined) this.status = status;
  }
}

const labRpcError = error => {
  const message = String(error?.message || '');
  const mapping = {
    '42501': ['LAB_FORBIDDEN', 'authorization', 403, 'You are not authorized to manage the Lab Product List.'],
    P4001: ['LAB_NOT_FOUND', 'not-found', 404, 'The selected lab no longer exists.'],
    P4002: ['LAB_NOT_ACTIVE', 'validation', 400, 'Archived labs cannot accept new products.'],
    P4003: ['LAB_PRODUCT_NOT_ACTIVE', 'validation', 400, 'The selected product is archived or unavailable.'],
    P4004: ['LAB_PRODUCT_NOT_FOUND', 'not-found', 404, 'The selected product no longer exists.'],
    P4005: ['LAB_CONSULTATION_NOT_ACTIVE', 'conflict', 409, 'Lab items can only be changed for an active consultation.'],
    P4006: ['LAB_CONSULTATION_NOT_FOUND', 'not-found', 404, 'The consultation could not be found.'],
    '23505': [
      message.includes('LAB_PRODUCT') ? 'LAB_PRODUCT_DUPLICATE' : 'LAB_DUPLICATE',
      'conflict', 409,
      message.includes('LAB_PRODUCT')
        ? 'A product with this name already exists for the selected lab.'
        : 'A lab with this name already exists.',
    ],
    '22023': ['LAB_INVALID_INPUT', 'validation', 400, 'Check the entered name and price, then try again.'],
  };
  const [code, kind, status, displayMessage] = mapping[error?.code] || [
    'LAB_RPC_FAILED', 'transport', undefined,
    'The Lab Product List request could not be completed.',
  ];
  return new LabApiError(displayMessage, { code, kind, status, cause: error });
};

export function createLabService({ supabaseClient } = {}) {
  const client = () => supabaseClient || getSupabaseClient();
  const rpc = async (name, args) => {
    const { data, error } = await client().rpc(name, args);
    if (error) throw labRpcError(error);
    return data;
  };
  return {
    listLabs: async (includeArchived = false) => (await rpc('list_labs', {
      p_include_archived: includeArchived,
    })) || [],
    createLab: name => rpc('create_lab', { p_name: name }),
    archiveLab: labId => rpc('archive_lab', { p_lab_id: labId }),
    listLabProducts: async (labId, includeArchived = false) => (await rpc('list_lab_products', {
      p_lab_id: labId,
      p_include_archived: includeArchived,
    })) || [],
    createLabProduct: (labId, name, currentPrice) => rpc('create_lab_product', {
      p_lab_id: labId,
      p_name: name,
      p_current_price: currentPrice,
    }),
    updateLabProductPrice: (productId, currentPrice) => rpc('update_lab_product_price', {
      p_lab_product_id: productId,
      p_current_price: currentPrice,
    }),
    archiveLabProduct: productId => rpc('archive_lab_product', {
      p_lab_product_id: productId,
    }),
    getConsultationLabItems: consultationId => rpc('get_consultation_lab_items', {
      p_consultation_id: consultationId,
    }),
    saveConsultationLabItems: (consultationId, items, labNote, labNoteSupplied = true) => rpc('save_consultation_lab_items', {
      p_consultation_id: consultationId,
      p_items: items.map(({ labProductId, quantity }) => ({ labProductId, quantity })),
      p_lab_note: labNote,
      p_lab_note_supplied: labNoteSupplied,
    }),
  };
}

export async function saveLabDraft({
  consultationId,
  ensureConsultationInitialized,
  items,
  labNote,
  save = saveConsultationLabItems,
}) {
  const resolved = consultationId
    ? { consultationId }
    : await ensureConsultationInitialized();
  if (!resolved?.consultationId) {
    throw new LabApiError('The consultation service did not return a consultation identifier.', {
      code: 'LAB_CONSULTATION_ID_MISSING', kind: 'validation',
    });
  }
  return save(resolved.consultationId, items, labNote, true);
}

const labService = createLabService();
export const listLabs = labService.listLabs;
export const createLab = labService.createLab;
export const archiveLab = labService.archiveLab;
export const listLabProducts = labService.listLabProducts;
export const createLabProduct = labService.createLabProduct;
export const updateLabProductPrice = labService.updateLabProductPrice;
export const archiveLabProduct = labService.archiveLabProduct;
export const getConsultationLabItems = labService.getConsultationLabItems;
export const saveConsultationLabItems = labService.saveConsultationLabItems;
