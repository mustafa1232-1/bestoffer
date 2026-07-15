const FEED_TRANSIENT_CACHE_TTL_MS = 10_000;
const HOT_RESPONSE_TTL_MS = 10_000;

export const transientFeedCache = new Map();
export const viewerScopeCache = new Map();
export const hotResponseCache = new Map();

export function getFeedTransientCacheTtlMs() {
  return FEED_TRANSIENT_CACHE_TTL_MS;
}

export function getFeedHotResponseTtlMs() {
  return HOT_RESPONSE_TTL_MS;
}

export function clearFeedTransientCaches() {
  transientFeedCache.clear();
  viewerScopeCache.clear();
}

export function clearFeedHotResponseCaches() {
  hotResponseCache.clear();
}

export function clearFeedMutationCaches() {
  clearFeedTransientCaches();
  clearFeedHotResponseCaches();
}
