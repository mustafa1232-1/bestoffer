/**
 * Shared phone / PIN normalisation helpers.
 *
 * Converts Arabic-Indic (٠١٢…) and Extended-Arabic-Indic (۰۱۲…) digits to
 * ASCII, then strips every non-digit character.
 */

/**
 * Replace Arabic-Indic / Extended-Arabic-Indic digit code-points with ASCII.
 * @param {string} value
 * @returns {string}
 */
export function normalizeDigits(value) {
  return String(value || "")
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

/**
 * Normalize a phone number: convert Arabic digits → ASCII, keep only digits.
 * @param {string} value
 * @returns {string}
 */
export function normalizePhone(value) {
  return normalizeDigits(value).replace(/[^\d]/g, "");
}

/**
 * Normalize a PIN: same as normalizePhone but semantically for PIN codes.
 * @param {string} value
 * @returns {string}
 */
export function normalizePin(value) {
  return normalizeDigits(value).replace(/[^\d]/g, "");
}
