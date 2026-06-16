import * as service from './sections.service.js';

function asBool(value, fallback = false) {
  if (value === true || value === false) return value;
  const normalized = String(value ?? '')
    .trim()
    .toLowerCase();
  if (normalized === 'true' || normalized === '1' || normalized === 'yes') {
    return true;
  }
  if (normalized === 'false' || normalized === '0' || normalized === 'no') {
    return false;
  }
  return fallback;
}

function asInt(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
}

export async function listPublicAvailability(req, res, next) {
  try {
    const out = await service.listPublicSectionAvailability({
      surfaceScope: req.query?.surfaceScope || req.query?.surface || 'user',
    });
    res.json({ items: out });
  } catch (error) {
    next(error);
  }
}

export async function listAdminAvailability(req, res, next) {
  try {
    const out = await service.listAdminSectionAvailability({
      surfaceScope: req.query?.surfaceScope || req.query?.surface || 'user',
    });
    res.json({ items: out });
  } catch (error) {
    next(error);
  }
}

export async function listAvailabilityAudit(req, res, next) {
  try {
    const out = await service.listSectionAvailabilityAudit({
      surfaceScope: req.query?.surfaceScope || req.query?.surface || 'user',
      sectionKey: req.query?.sectionKey || null,
      limit: asInt(req.query?.limit, 80),
    });
    res.json({ items: out });
  } catch (error) {
    next(error);
  }
}

export async function updateAvailability(req, res, next) {
  try {
    const out = await service.updateSectionAvailability({
      sectionKey: req.params.sectionKey,
      actorUserId: req.userId,
      dto: {
        displayName: req.body?.displayName,
        parentSectionKey: req.body?.parentSectionKey,
        surfaceScope: req.body?.surfaceScope || req.body?.surface || 'user',
        status: req.body?.status,
        isVisible: asBool(req.body?.isVisible, true),
        userMessage: req.body?.userMessage,
        sortOrder: asInt(req.body?.sortOrder, 0),
        allowExistingActiveAccess: asBool(
          req.body?.allowExistingActiveAccess,
          true
        ),
        metadata:
          req.body?.metadata && typeof req.body.metadata === 'object'
            ? req.body.metadata
            : {},
      },
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}
