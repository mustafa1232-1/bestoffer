/**
 * Purpose:
 * controllers أدلة الاستخدام (المرحلة 10). دليل عام scope-aware + إدارة المحتوى.
 */

import * as service from "./guides.service.js";
import { recordAudit, auditContextFromReq } from "../security/audit.service.js";

export async function getGuide(req, res, next) {
  try {
    const appScope = String(req.query?.appScope || "").trim();
    const out = await service.getGuide({
      appScope,
      viewerUserId: req.userId || null,
    });
    res.set("Cache-Control", "public, max-age=300");
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function adminListSections(req, res, next) {
  try {
    const appScope = String(req.query?.appScope || "").trim();
    const items = await service.adminListSections(appScope);
    return res.json({ items });
  } catch (error) {
    return next(error);
  }
}

export async function upsertSection(req, res, next) {
  try {
    const section = await service.upsertSection({
      actorUserId: req.userId,
      dto: req.body || {},
    });
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "settings.guides.manage",
      summary: `تحديث دليل ${section.app_scope}/${section.section_key}`,
      targetType: "app_guide_section",
      targetId: section.id,
      permissionKey: "settings.guides.manage",
    });
    return res.status(201).json({ section });
  } catch (error) {
    return next(error);
  }
}
