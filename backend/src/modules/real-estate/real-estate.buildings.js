export const BUILDING_COUNTS = Object.freeze({
  A1: 12, A2: 14, A3: 14, A4: 12, A5: 12, A6: 12, A7: 13, A8: 15, A9: 15,
  B1: 12, B2: 18, B3: 18, B4: 12, B5: 18, B6: 21, B7: 16, B8: 12,
});

export function isKnownBlock(value) {
  return Object.prototype.hasOwnProperty.call(BUILDING_COUNTS, String(value || '').trim().toUpperCase());
}

export function isValidBuildingNumber(block, buildingNumber) {
  const normalizedBlock = String(block || '').trim().toUpperCase();
  const normalizedBuilding = String(buildingNumber || '').trim().toUpperCase();
  const count = BUILDING_COUNTS[normalizedBlock];
  if (!count || !normalizedBuilding) return false;

  const sequence = Number(normalizedBuilding);
  if (Number.isInteger(sequence) && sequence >= 1 && sequence <= count) return true;

  if (normalizedBuilding.startsWith(normalizedBlock)) {
    const codeSequence = Number(normalizedBuilding.slice(normalizedBlock.length));
    if (Number.isInteger(codeSequence) && codeSequence >= 1 && codeSequence <= count) {
      return true;
    }
  }

  const blockNumber = Number(normalizedBlock.slice(1));
  const legacyNumber = Number(normalizedBuilding);
  return (
    Number.isInteger(legacyNumber) &&
    legacyNumber >= blockNumber * 100 + 1 &&
    legacyNumber <= blockNumber * 100 + count
  );
}
