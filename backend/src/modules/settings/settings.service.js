/**
 * Purpose:
 * إعدادات الدعم المركزية (المرحلة 8). رقم دعم واحد لكل التطبيقات، يُحدَّث دون
 * تحديث التطبيق، بتحقق صيغة E164 ومنع حقن روابط/نصوص ضارة، مع تدقيق كامل.
 */

import { AppError } from "../../shared/utils/errors.js";
import * as repo from "./settings.repo.js";

export const SUPPORT_SETTING_KEY = "support_contact";

const E164_RE = /^\+[1-9]\d{7,14}$/;

function cleanText(value, max) {
  if (value == null) return null;
  // منع الحقن: إزالة أحرف التحكم (فئة Unicode Cc) والأقواس الزاوية.
  const text = String(value)
    .replace(/\p{Cc}/gu, "")
    .replace(/[<>]/g, "")
    .trim();
  if (!text) return null;
  return text.slice(0, max);
}

function normalizePhone(value) {
  if (value == null) return null;
  const text = String(value).replace(/[\s\-()]/g, "").trim();
  return text || null;
}

export function validateSupportContact(dto = {}) {
  const errors = {};
  const value = {};

  const phone = normalizePhone(dto.supportPhoneE164);
  if (phone != null) {
    if (!E164_RE.test(phone)) errors.supportPhoneE164 = "INVALID_E164";
    else value.supportPhoneE164 = phone;
  }

  const emergency = normalizePhone(dto.supportEmergencyPhone);
  if (emergency != null) {
    if (!E164_RE.test(emergency)) errors.supportEmergencyPhone = "INVALID_E164";
    else value.supportEmergencyPhone = emergency;
  }

  const whatsapp = normalizePhone(dto.supportWhatsApp);
  if (whatsapp != null) {
    if (!E164_RE.test(whatsapp)) errors.supportWhatsApp = "INVALID_E164";
    else value.supportWhatsApp = whatsapp;
  }

  const display = cleanText(dto.supportPhoneDisplay, 40);
  if (display) value.supportPhoneDisplay = display;

  const hours = cleanText(dto.supportWorkingHours, 120);
  if (hours) value.supportWorkingHours = hours;

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    value,
  };
}

export async function getSupportContact() {
  const row = await repo.getSetting(SUPPORT_SETTING_KEY);
  const value = row?.value_json || {};
  return {
    supportPhoneE164: value.supportPhoneE164 || null,
    supportPhoneDisplay: value.supportPhoneDisplay || null,
    supportWhatsApp: value.supportWhatsApp || null,
    supportWorkingHours: value.supportWorkingHours || null,
    supportEmergencyPhone: value.supportEmergencyPhone || null,
    updatedAt: row?.updated_at || null,
  };
}

/**
 * إعدادات عامة آمنة للتطبيقات (لا تكشف بيانات حساسة).
 */
export async function getPublicSettings() {
  const support = await getSupportContact();
  return { support };
}

export async function updateSupportContact({ actorUserId, dto }) {
  const v = validateSupportContact(dto || {});
  if (!v.ok) {
    throw new AppError("VALIDATION_ERROR", {
      status: 400,
      details: { fields: v.errors },
    });
  }
  const before = await getSupportContact();
  const saved = await repo.upsertSetting({
    key: SUPPORT_SETTING_KEY,
    value: v.value,
    actorUserId,
  });
  return { before, after: saved.value_json, updatedAt: saved.updated_at };
}
