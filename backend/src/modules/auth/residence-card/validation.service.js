function normalizeArabicDigits(input) {
  return String(input || "")
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

function cleanString(value) {
  const text = String(value || "").trim();
  return text || null;
}

function cleanNumeric(value) {
  const digits = normalizeArabicDigits(String(value || "")).replace(/[^\d]/g, "");
  return digits || null;
}

function isIsoDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ""))) return false;
  const d = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(d.getTime())) return false;
  return d.toISOString().slice(0, 10) === value;
}

export function validateResidenceCardExtraction(parsed) {
  const warnings = [...(parsed?.warnings || [])];
  const normalized = {
    full_name: cleanString(parsed?.extractedData?.full_name),
    town: cleanString(parsed?.extractedData?.town)?.toUpperCase() || null,
    building_number: cleanNumeric(parsed?.extractedData?.building_number),
    issue_date: cleanString(parsed?.extractedData?.issue_date),
    contract_number: cleanNumeric(parsed?.extractedData?.contract_number),
    floor_number: cleanNumeric(parsed?.extractedData?.floor_number),
    apartment_number: cleanNumeric(parsed?.extractedData?.apartment_number),
    visible_id_number: cleanNumeric(parsed?.extractedData?.visible_id_number),
  };

  if (normalized.full_name) {
    const length = normalized.full_name.length;
    const words = normalized.full_name.split(/\s+/g).filter(Boolean).length;
    if (length < 4 || length > 180 || words < 2) {
      warnings.push("تم تجاهل الاسم المستخرج لعدم تطابقه مع الصيغة المتوقعة");
      normalized.full_name = null;
    }
  }

  if (normalized.town && !/^[A-Z]$/.test(normalized.town)) {
    warnings.push("تم تجاهل قيمة البلوك لعدم مطابقتها للصيغة المتوقعة");
    normalized.town = null;
  }

  const numericRules = [
    ["building_number", normalized.building_number, 1, 5, "رقم البناية"],
    ["floor_number", normalized.floor_number, 1, 3, "رقم الطابق"],
    ["apartment_number", normalized.apartment_number, 1, 4, "رقم الشقة"],
    ["contract_number", normalized.contract_number, 3, 20, "رقم العقد"],
    ["visible_id_number", normalized.visible_id_number, 2, 20, "رقم الهوية"],
  ];

  for (const [field, value, min, max, label] of numericRules) {
    if (!value) continue;
    if (value.length < min || value.length > max) {
      warnings.push(`تم تجاهل ${label} لعدم مطابقته الصيغة المتوقعة`);
      normalized[field] = null;
    }
  }

  if (normalized.issue_date && !isIsoDate(normalized.issue_date)) {
    warnings.push("تم تجاهل تاريخ الإصدار لعدم مطابقته صيغة التاريخ");
    normalized.issue_date = null;
  }

  const missingFields = Object.entries(normalized)
    .filter(([, value]) => value == null || value === "")
    .map(([key]) => key);

  return {
    ...parsed,
    extractedData: normalized,
    missingFields,
    warnings,
    confidence: Number(parsed?.confidence || 0),
  };
}
