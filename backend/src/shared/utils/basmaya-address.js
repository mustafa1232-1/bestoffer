function normalizeDigits(value) {
  return String(value || "")
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

function normalizeCode(value) {
  return normalizeDigits(value).trim().toUpperCase();
}

function parseBlock(blockCode) {
  const normalized = normalizeCode(blockCode);
  const match = /^([AB])([1-9])$/.exec(normalized);
  if (!match) return null;

  const letter = match[1];
  const sector = Number(match[2]);
  if (letter === "B" && sector > 8) return null;

  return { normalized, letter, sector };
}

function parseBuilding(buildingCode) {
  const normalized = normalizeCode(buildingCode);
  const match = /^([AB])([1-9])(0[1-9]|1[0-9]|2[0-2])$/.exec(normalized);
  if (!match) return null;

  const letter = match[1];
  const sector = Number(match[2]);
  const buildingNo = Number(match[3]);

  if (letter === "B" && sector > 8) return null;
  if (!isBuildingWithinRange(letter, buildingNo)) return null;

  return {
    normalized,
    letter,
    sector,
    buildingNo,
  };
}

function normalizeBuildingWithBlock(buildingCode, parsedBlock) {
  const normalized = normalizeCode(buildingCode);
  if (!normalized) return null;

  const full = /^([AB])([1-9])(0[1-9]|1[0-9]|2[0-2])$/.exec(normalized);
  if (full) return normalized;
  if (!parsedBlock) return null;

  // Support legacy input like "11" -> "A711" when block is A7.
  const twoDigits = /^(0[1-9]|1[0-9]|2[0-2])$/.exec(normalized);
  if (twoDigits) {
    return `${parsedBlock.letter}${parsedBlock.sector}${twoDigits[1]}`;
  }

  // Support legacy input like "711" (sector + buildingNo).
  const threeDigits = /^([1-9])(0[1-9]|1[0-9]|2[0-2])$/.exec(normalized);
  if (threeDigits) {
    const sector = Number(threeDigits[1]);
    if (sector !== parsedBlock.sector) return null;
    return `${parsedBlock.letter}${threeDigits[0]}`;
  }

  return null;
}

function isBuildingWithinRange(letter, buildingNo) {
  if (!Number.isInteger(buildingNo)) return false;
  if (letter === "A") return buildingNo >= 1 && buildingNo <= 12;
  if (letter === "B") return buildingNo >= 1 && buildingNo <= 22;
  return false;
}

function isApartmentValid(apartmentCode) {
  const normalized = normalizeCode(apartmentCode);
  const groundMatch = /^G(0[1-9]|1[0-2])$/.exec(normalized);
  if (groundMatch) return true;

  const floorMatch = /^([1-9])(0[1-9]|1[0-2])$/.exec(normalized);
  if (!floorMatch) return false;

  const floor = Number(floorMatch[1]);
  return floor >= 1 && floor <= 9;
}

export function normalizeBasmayaAddress(address = {}) {
  return {
    block: normalizeCode(address.block),
    buildingNumber: normalizeCode(address.buildingNumber),
    apartment: normalizeCode(address.apartment),
  };
}

export function deriveBasmayaHierarchy(address = {}) {
  const normalized = normalizeBasmayaAddress(address);
  const parsedBlock = parseBlock(normalized.block);
  const parsedBuilding = parseBuilding(normalized.buildingNumber);

  const block = parsedBlock?.letter || parsedBuilding?.letter || null;
  const compound =
    parsedBlock?.normalized ||
    (parsedBuilding ? `${parsedBuilding.letter}${parsedBuilding.sector}` : null);
  const building = parsedBuilding?.normalized || null;

  return {
    block,
    compound,
    building,
    apartment: normalized.apartment || null,
  };
}

export function normalizeCommunityScope(scopeType, scopeCode) {
  const type = normalizeCode(scopeType).toLowerCase();
  const code = normalizeCode(scopeCode);
  if (!["block", "compound", "building"].includes(type)) {
    return { ok: false, scopeType: null, scopeCode: null, errors: ["scopeType"] };
  }

  if (type === "block") {
    if (!/^[AB]$/.test(code)) {
      return { ok: false, scopeType: type, scopeCode: null, errors: ["scopeCode"] };
    }
    return { ok: true, scopeType: type, scopeCode: code, errors: [] };
  }

  if (type === "compound") {
    const parsed = parseBlock(code);
    if (!parsed) {
      return { ok: false, scopeType: type, scopeCode: null, errors: ["scopeCode"] };
    }
    return {
      ok: true,
      scopeType: type,
      scopeCode: parsed.normalized,
      errors: [],
    };
  }

  const parsedBuilding = parseBuilding(code);
  if (!parsedBuilding) {
    return { ok: false, scopeType: type, scopeCode: null, errors: ["scopeCode"] };
  }
  return {
    ok: true,
    scopeType: type,
    scopeCode: parsedBuilding.normalized,
    errors: [],
  };
}

export function validateBasmayaAddress(address = {}) {
  const normalized = normalizeBasmayaAddress(address);
  const errors = [];

  const parsedBlock = parseBlock(normalized.block);
  if (!parsedBlock) {
    errors.push("block");
  }

  const normalizedBuilding = normalizeBuildingWithBlock(
    normalized.buildingNumber,
    parsedBlock
  );
  if (normalizedBuilding) {
    normalized.buildingNumber = normalizedBuilding;
  }

  const buildingMatch = /^([AB])([1-9])(0[1-9]|1[0-9]|2[0-2])$/.exec(
    normalized.buildingNumber
  );
  if (!buildingMatch) {
    errors.push("buildingNumber");
  } else if (parsedBlock) {
    const buildingLetter = buildingMatch[1];
    const buildingSector = Number(buildingMatch[2]);
    const buildingNo = Number(buildingMatch[3]);
    const sameSector =
      buildingLetter === parsedBlock.letter &&
      buildingSector === parsedBlock.sector;
    if (!sameSector || !isBuildingWithinRange(buildingLetter, buildingNo)) {
      errors.push("buildingNumber");
    }
  } else {
    const buildingLetter = buildingMatch[1];
    const buildingNo = Number(buildingMatch[3]);
    if (!isBuildingWithinRange(buildingLetter, buildingNo)) {
      errors.push("buildingNumber");
    }
  }

  if (!isApartmentValid(normalized.apartment)) {
    errors.push("apartment");
  }

  return {
    ok: errors.length === 0,
    errors,
    normalized,
  };
}
