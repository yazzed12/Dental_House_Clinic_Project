export const filterLabProducts = (products, search) => {
  const query = String(search || '').trim().toLocaleLowerCase();
  if (!query) return products;
  return products.filter(product => String(product.name || '').toLocaleLowerCase().includes(query));
};

export const chooseLabAfterRefresh = (labs, currentLabId, preferredLabId) => {
  if (preferredLabId && labs.some(lab => lab.id === preferredLabId)) return preferredLabId;
  if (currentLabId && labs.some(lab => lab.id === currentLabId)) return currentLabId;
  return labs.find(lab => lab.isActive)?.id || labs[0]?.id || null;
};
