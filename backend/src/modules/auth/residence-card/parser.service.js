const FIELD_KEYS = [
  "full_name",
  "town",
  "building_number",
  "issue_date",
  "contract_number",
  "floor_number",
  "apartment_number",
  "visible_id_number",
];

const LABEL_SYNONYMS = {
  full_name: ["الاسم", "الاسم الكامل", "name", "full name"],
  visible_id_number: ["رقم الهوية", "هوية", "id number", "identity number"],
  issue_date: ["تاريخ الاصدار", "تاريخ الإصدار", "issue date", "date of issue"],
  contract_number: ["رقم العقد", "contract", "contract number"],
  floor_number: ["رقم الطابق", "الطابق", "floor", "floor number"],
  apartment_number: ["رقم الشقة", "الشقة", "apartment", "apartment number", "flat number"],
  building_number: ["رقم البناية", "البناية", "العمارة", "building", "building number"],
  town: ["town", "بلوك", "البلوك", "القطاع"],
};

const FIELD_WEIGHTS = {
  full_name: 0.2,
  town: 0.1,
  building_number: 0.15,
  issue_date: 0.15,
  contract_number: 0.1,
  floor_number: 0.1,
  apartment_number: 0.1,
  visible_id_number: 0.1,
};

function normalizeArabicDigits(input) {
  return String(input || "")
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

function normalizeText(input) {
  return normalizeArabicDigits(input)
    .replace(/[ـ]/g, "")
    .replace(/[“”"']/g, "")
    .replace(/[،؛]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function toLines(text) {
  return String(text || "")
    .split(/\r?\n/g)
    .map((line) => normalizeText(line))
    .filter(Boolean);
}

function hasLabel(line, labels) {
  const normalized = normalizeText(line).toLowerCase();
  return labels.some((label) => normalized.includes(normalizeText(label).toLowerCase()));
}

function extractNumericCandidate(raw) {
  const candidate = normalizeArabicDigits(String(raw || "")).replace(/[^\d]/g, "");
  return candidate || null;
}

function extractTownCandidate(raw) {
  const match = normalizeText(raw).match(/\b(?:town|بلوك|البلوك|القطاع)\s*[:\-]?\s*([A-Za-z])\b/i);
  if (match?.[1]) return match[1].toUpperCase();
  const direct = normalizeText(raw).match(/\b([A-Za-z])\b/);
  return direct?.[1] ? direct[1].toUpperCase() : null;
}

function extractInlineValue(line, labels) {
  const normalizedLine = normalizeText(line);
  for (const label of labels) {
    const escaped = normalizeText(label).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`${escaped}\\s*[:\\-]?\\s*(.+)$`, "i");
    const m = normalizedLine.match(re);
    if (m?.[1]) {
      const value = normalizeText(m[1]);
      if (value) return value;
    }
  }
  return null;
}

function isLikelyLabelLine(line) {
  const normalized = normalizeText(line).toLowerCase();
  return Object.values(LABEL_SYNONYMS)
    .flat()
    .some((label) => normalized.includes(normalizeText(label).toLowerCase()));
}

function nearestNonLabelValue(lines, index) {
  const offsets = [1, -1, 2, -2];
  for (const offset of offsets) {
    const candidate = lines[index + offset];
    if (!candidate) continue;
    if (isLikelyLabelLine(candidate)) continue;
    return normalizeText(candidate);
  }
  return null;
}

function parseIsoDate(value) {
  const normalized = normalizeArabicDigits(String(value || "")).replace(/\s+/g, "");
  const m = normalized.match(/(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})/);
  if (!m) return null;
  const day = Number(m[1]);
  const month = Number(m[2]);
  const year = Number(m[3]);
  if (!Number.isInteger(day) || !Number.isInteger(month) || !Number.isInteger(year)) {
    return null;
  }
  if (day < 1 || day > 31 || month < 1 || month > 12 || year < 1900 || year > 2100) {
    return null;
  }
  const iso = `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}-${String(
    day
  ).padStart(2, "0")}`;
  const parsed = new Date(`${iso}T00:00:00.000Z`);
  if (Number.isNaN(parsed.getTime())) return null;
  return iso;
}

function fallbackFullName(lines) {
  const candidates = lines
    .map((line) => normalizeText(line))
    .filter((line) => /[\u0600-\u06FF]/.test(line))
    .filter((line) => !isLikelyLabelLine(line))
    .filter((line) => !/\d/.test(line))
    .filter((line) => line.split(" ").length >= 2)
    .sort((a, b) => b.length - a.length);
  return candidates[0] || null;
}

function parseByLabel(lines, fieldKey) {
  const labels = LABEL_SYNONYMS[fieldKey] || [];
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (!hasLabel(line, labels)) continue;
    const inline = extractInlineValue(line, labels);
    if (inline) return inline;
    const neighbor = nearestNonLabelValue(lines, i);
    if (neighbor) return neighbor;
  }
  return null;
}

function detectDocumentType(text) {
  const normalized = normalizeText(text).toLowerCase();
  const hits = [
    "basmaya residence card",
    "مدينة بسماية",
    "هوية ساكني مدينة بسماية",
    "town",
    "رقم العقد",
    "رقم البناية",
  ].filter((keyword) => normalized.includes(keyword.toLowerCase())).length;
  return hits >= 2 ? "residence_card" : "unknown";
}

function buildConfidence(data, documentType, rawTextLength = 0) {
  let score = 0;
  for (const field of FIELD_KEYS) {
    if (data[field]) score += FIELD_WEIGHTS[field] || 0;
  }
  if (documentType === "residence_card") score += 0.05;
  if (rawTextLength < 40) score *= 0.75;
  if (rawTextLength > 250) score += 0.05;
  return Math.max(0, Math.min(0.99, Number(score.toFixed(2))));
}

export function parseResidenceCardText(rawText) {
  const lines = toLines(rawText);
  const documentType = detectDocumentType(rawText);
  const data = {
    full_name: null,
    town: null,
    building_number: null,
    issue_date: null,
    contract_number: null,
    floor_number: null,
    apartment_number: null,
    visible_id_number: null,
  };

  data.full_name = parseByLabel(lines, "full_name") || fallbackFullName(lines);
  data.visible_id_number = extractNumericCandidate(parseByLabel(lines, "visible_id_number"));
  data.contract_number = extractNumericCandidate(parseByLabel(lines, "contract_number"));
  data.floor_number = extractNumericCandidate(parseByLabel(lines, "floor_number"));
  data.apartment_number = extractNumericCandidate(parseByLabel(lines, "apartment_number"));
  data.building_number = extractNumericCandidate(parseByLabel(lines, "building_number"));
  data.town = extractTownCandidate(
    parseByLabel(lines, "town") || lines.find((line) => /\btown\b/i.test(line)) || ""
  );
  data.issue_date = parseIsoDate(parseByLabel(lines, "issue_date"));

  const missingFields = FIELD_KEYS.filter((key) => !data[key]);
  const warnings = [];
  if (missingFields.length > 0) {
    warnings.push("بعض الحقول لم يتم استخراجها ويجب مراجعتها يدويًا");
  }
  if (documentType !== "residence_card") {
    warnings.push("تعذر تأكيد نوع المستند بشكل كامل، يرجى مراجعة البيانات يدويًا");
  }

  const confidence = buildConfidence(data, documentType, String(rawText || "").length);
  return {
    documentType,
    confidence,
    extractedData: data,
    missingFields,
    warnings,
    lines,
  };
}
