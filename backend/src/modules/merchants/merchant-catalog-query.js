export function normalizeCatalogQuery(query = {}) {
  const boundedInteger = (value, fallback, min, max) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) && value !== '' && value != null
      ? Math.max(min, Math.min(max, Math.floor(parsed))) : fallback;
  };
  const positiveId = (value) => Number.isSafeInteger(Number(value)) && Number(value) > 0 ? Number(value) : null;
  const ids = query.productIds == null ? null : [...new Set(
    String(query.productIds).split(',').map(positiveId).filter(Boolean)
  )].slice(0, 500);
  const sort = ['recommended', 'priceLowToHigh', 'priceHighToLow', 'biggestDiscount'].includes(query.sort)
    ? query.sort : 'recommended';
  return {
    limit: boundedInteger(query.limit, 200, 1, 200),
    offset: boundedInteger(query.offset, 0, 0, 2147483647),
    search: String(query.search || '').trim().slice(0, 200),
    categoryId: positiveId(query.categoryId),
    productIds: ids,
    onlyAvailable: query.onlyAvailable === true || query.onlyAvailable === 'true',
    onlyOffers: query.onlyOffers === true || query.onlyOffers === 'true',
    sort,
  };
}
