/**
 * Purpose:
 * تجهيز دليل الاستخدام حسب التطبيق والصلاحيات (المرحلة 10). في نطاق الإدارة
 * تُحذف الأقسام التي لا يملك الموظف صلاحيتها (لا تُعرض خطوة لمسار غير متاح).
 */

import { AppError } from "../../shared/utils/errors.js";
import * as repo from "./guides.repo.js";
import { resolveEffectivePermissions } from "../security/permissions.service.js";

const VALID_SCOPES = ["user", "store", "captain", "delivery", "admin"];

export function isValidScope(scope) {
  return VALID_SCOPES.includes(String(scope || ""));
}

function hasPermission(effective, key) {
  if (!key) return true;
  if (!effective) return false;
  if (effective.isSuperAdmin || effective.permissions === "ALL") return true;
  return effective.permissions instanceof Map && effective.permissions.has(key);
}

export async function getGuide({ appScope, viewerUserId = null }) {
  if (!isValidScope(appScope)) {
    throw new AppError("INVALID_GUIDE_SCOPE", { status: 400 });
  }
  const [sections, versionInfo] = await Promise.all([
    repo.listSections({ appScope, publishedOnly: true }),
    repo.guideVersion(appScope),
  ]);

  let visible = sections;
  if (appScope === "admin") {
    // scope-aware: أخفِ الأقسام التي تتطلب صلاحية لا يملكها الموظف.
    const effective = viewerUserId
      ? await resolveEffectivePermissions(viewerUserId)
      : null;
    visible = sections.filter((s) => hasPermission(effective, s.required_permission));
  } else {
    // خارج نطاق الإدارة لا نكشف أقساماً مقيّدة بصلاحية.
    visible = sections.filter((s) => !s.required_permission);
  }

  return {
    appScope,
    version: versionInfo.version,
    sectionsCount: visible.length,
    sections: visible.map((s) => ({
      key: s.section_key,
      title: s.title,
      body: s.body,
      orderIndex: s.order_index,
      deepLink: s.deep_link || null,
    })),
  };
}

export async function adminListSections(appScope) {
  if (!isValidScope(appScope)) {
    throw new AppError("INVALID_GUIDE_SCOPE", { status: 400 });
  }
  return repo.listSections({ appScope, publishedOnly: false });
}

export async function upsertSection({ actorUserId, dto }) {
  if (!isValidScope(dto?.appScope)) {
    throw new AppError("INVALID_GUIDE_SCOPE", { status: 400 });
  }
  const sectionKey = String(dto?.sectionKey || "").trim();
  const title = String(dto?.title || "").trim();
  const body = String(dto?.body || "").trim();
  if (!sectionKey || !title || !body) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: ["sectionKey", "title", "body"] },
    });
  }
  return repo.upsertSection({
    appScope: dto.appScope,
    sectionKey,
    title,
    body,
    orderIndex: dto.orderIndex,
    requiredPermission: dto.requiredPermission || null,
    deepLink: dto.deepLink || null,
    isPublished: dto.isPublished,
    actorUserId,
  });
}
