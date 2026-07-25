/**
 * Purpose:
 * controllers إعدادات المنصّة (المرحلة 8). endpoint عام للتطبيقات + endpoints
 * إدارية محمية بصلاحية settings.support_phone.update، مع تدقيق التغيير.
 */

import * as service from "./settings.service.js";
import { recordAudit, auditContextFromReq } from "../security/audit.service.js";

export async function publicSettings(req, res, next) {
  try {
    const out = await service.getPublicSettings();
    // cache قصير على الحافة/العميل؛ يتغير نادراً.
    res.set("Cache-Control", "public, max-age=300");
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getSupport(req, res, next) {
  try {
    const out = await service.getSupportContact();
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function updateSupport(req, res, next) {
  try {
    const out = await service.updateSupportContact({
      actorUserId: req.userId,
      dto: req.body || {},
    });
    void recordAudit({
      ...auditContextFromReq(req),
      actionKey: "settings.support_phone.update",
      summary: "تحديث إعدادات رقم الدعم المركزي",
      targetType: "platform_setting",
      targetLabel: "support_contact",
      permissionKey: "settings.support_phone.update",
      before: out.before,
      after: out.after,
    });
    return res.json({ support: await service.getSupportContact() });
  } catch (error) {
    return next(error);
  }
}
