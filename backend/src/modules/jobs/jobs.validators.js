import {
  JOB_ACTIVITY_TYPES,
  JOB_DEPARTMENTS_BY_ACTIVITY,
  isDepartmentAllowedForActivity,
  isKnownActivityType,
  isKnownDepartment,
} from "./jobs.taxonomy.js";

function toTrimmedString(value, { max = 5000, fallback = "" } = {}) {
  if (value === undefined || value === null) return fallback;
  const normalized = String(value).trim();
  if (!normalized) return fallback;
  return normalized.length > max ? normalized.slice(0, max) : normalized;
}

function toNullableString(value, { max = 5000 } = {}) {
  const normalized = toTrimmedString(value, { max, fallback: "" });
  return normalized || null;
}

function toNullableEmail(value) {
  const normalized = toNullableString(value, { max: 180 });
  if (!normalized) return null;
  const looksLikeEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized);
  if (!looksLikeEmail) return null;
  return normalized.toLowerCase();
}

function toPositiveInt(value, { min = 1, max = 100000 } = {}) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) return null;
  if (parsed < min || parsed > max) return null;
  return parsed;
}

function toNonNegativeNumber(value) {
  if (value === undefined || value === null || value === "") return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return null;
  return parsed;
}

function toBool(value, fallback = false) {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value !== 0;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["1", "true", "yes", "y", "on"].includes(normalized)) return true;
    if (["0", "false", "no", "n", "off"].includes(normalized)) return false;
  }
  return fallback;
}

function toIsoDate(value) {
  if (value === undefined || value === null || value === "") return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

function splitSkills(value) {
  if (Array.isArray(value)) {
    return value
      .map((item) => toTrimmedString(item, { max: 80, fallback: "" }))
      .filter(Boolean)
      .slice(0, 30);
  }

  const text = toTrimmedString(value, { max: 1200, fallback: "" });
  if (!text) return [];
  return text
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, 30);
}

const employmentTypes = new Set([
  "full_time",
  "part_time",
  "contract",
  "internship",
  "freelance",
]);
const workplaceTypes = new Set(["on_site", "hybrid", "remote"]);
const experienceLevels = new Set([
  "entry",
  "junior",
  "mid",
  "senior",
  "lead",
  "manager",
]);
const salaryPeriods = new Set(["hourly", "monthly", "yearly", "project"]);
const jobStatuses = new Set(["draft", "active", "paused", "closed"]);
const applicationStatuses = new Set([
  "submitted",
  "shortlisted",
  "rejected",
  "hired",
  "withdrawn",
  "dismissed_after_hire",
  "archived",
]);
const jobSortOptions = new Set([
  "recent",
  "salary_high",
  "salary_low",
  "expires_soon",
]);

function normalizeActivityType(value, fallback = null) {
  const normalized = toTrimmedString(value, { max: 80, fallback: "" })
    .toLowerCase()
    .replace(/-/g, "_");
  if (!normalized) return fallback;
  return isKnownActivityType(normalized) ? normalized : null;
}

function normalizeDepartment(value, fallback = null) {
  const normalized = toTrimmedString(value, { max: 120, fallback: "" })
    .toLowerCase()
    .replace(/-/g, "_");
  if (!normalized) return fallback;
  return isKnownDepartment(normalized) ? normalized : null;
}

function normalizeEnum(value, allowed, fallback) {
  const normalized = toTrimmedString(value, { max: 40, fallback: "" })
    .toLowerCase()
    .replace(/-/g, "_");
  if (!normalized) return fallback;
  return allowed.has(normalized) ? normalized : null;
}

export function validateJobId(value) {
  const parsed = toPositiveInt(value, { min: 1, max: Number.MAX_SAFE_INTEGER });
  if (!parsed) {
    return { ok: false, errors: ["jobId"] };
  }
  return { ok: true, value: parsed };
}

export function validateApplicationId(value) {
  const parsed = toPositiveInt(value, { min: 1, max: Number.MAX_SAFE_INTEGER });
  if (!parsed) {
    return { ok: false, errors: ["applicationId"] };
  }
  return { ok: true, value: parsed };
}

export function validateListJobsQuery(query = {}) {
  const errors = [];

  const page = toPositiveInt(query.page, { min: 1, max: 100000 }) || 1;
  const limit = toPositiveInt(query.limit, { min: 1, max: 100 }) || 20;
  const search = toNullableString(query.search, { max: 120 });
  const category = toNullableString(query.category, { max: 120 });
  const city = toNullableString(query.city, { max: 120 });
  const area = toNullableString(query.area, { max: 120 });
  const activityType = normalizeActivityType(query.activityType, null);
  const department = normalizeDepartment(query.department, null);
  const employmentType = normalizeEnum(
    query.employmentType,
    employmentTypes,
    null
  );
  const workplaceType = normalizeEnum(
    query.workplaceType,
    workplaceTypes,
    null
  );
  const experienceLevel = normalizeEnum(
    query.experienceLevel,
    experienceLevels,
    null
  );
  const sort = normalizeEnum(query.sort, jobSortOptions, "recent");
  const onlyOpen = toBool(query.onlyOpen, true);
  const status = query.status == null
    ? null
    : normalizeEnum(query.status, jobStatuses, null);
  const minSalary = toNonNegativeNumber(query.minSalary);
  const maxSalary = toNonNegativeNumber(query.maxSalary);

  if (query.employmentType !== undefined && employmentType == null) {
    errors.push("employmentType");
  }
  if (query.workplaceType !== undefined && workplaceType == null) {
    errors.push("workplaceType");
  }
  if (query.experienceLevel !== undefined && experienceLevel == null) {
    errors.push("experienceLevel");
  }
  if (query.sort !== undefined && sort == null) {
    errors.push("sort");
  }
  if (query.activityType !== undefined && activityType == null) {
    errors.push("activityType");
  }
  if (query.department !== undefined && department == null) {
    errors.push("department");
  }
  if (
    activityType != null &&
    department != null &&
    !isDepartmentAllowedForActivity(activityType, department)
  ) {
    errors.push("activityDepartment");
  }
  if (query.status !== undefined && status == null) {
    errors.push("status");
  }
  if (
    minSalary != null &&
    maxSalary != null &&
    Number.isFinite(minSalary) &&
    Number.isFinite(maxSalary) &&
    maxSalary < minSalary
  ) {
    errors.push("salaryRange");
  }

  if (errors.length > 0) return { ok: false, errors };

  return {
    ok: true,
    value: {
      page,
      limit,
      search,
      category,
      city,
      area,
      activityType,
      department,
      employmentType,
      workplaceType,
      experienceLevel,
      sort: sort || "recent",
      onlyOpen,
      status,
      minSalary,
      maxSalary,
    },
  };
}

export function validateCreateJobBody(body = {}) {
  const errors = [];

  const title = toTrimmedString(body.title, { max: 180, fallback: "" });
  const companyName = toNullableString(body.companyName, { max: 180 });
  const companyLogoUrl = toNullableString(body.companyLogoUrl, { max: 1200 });
  const category = toTrimmedString(body.category, { max: 120, fallback: "" });
  const activityType = normalizeActivityType(body.activityType, null);
  const department = normalizeDepartment(body.department, null);
  const city = toTrimmedString(body.city, { max: 120, fallback: "" });
  const area = toNullableString(body.area, { max: 120 });
  const description = toTrimmedString(body.description, {
    max: 12000,
    fallback: "",
  });
  const requirements = toNullableString(body.requirements, { max: 12000 });
  const responsibilities = toNullableString(body.responsibilities, {
    max: 12000,
  });
  const benefits = toNullableString(body.benefits, { max: 12000 });
  const skills = splitSkills(body.skills);
  const contactPhone = toNullableString(body.contactPhone, { max: 30 });
  const contactEmail = toNullableString(body.contactEmail, { max: 180 });
  const applyUrl = toNullableString(body.applyUrl, { max: 1200 });
  const educationLevel = toNullableString(body.educationLevel, { max: 80 });
  const workplaceType = normalizeEnum(
    body.workplaceType,
    workplaceTypes,
    "on_site"
  );
  const employmentType = normalizeEnum(
    body.employmentType,
    employmentTypes,
    "full_time"
  );
  const experienceLevel = normalizeEnum(
    body.experienceLevel,
    experienceLevels,
    "mid"
  );
  const salaryPeriod = normalizeEnum(body.salaryPeriod, salaryPeriods, "monthly");
  const salaryCurrency =
    toTrimmedString(body.salaryCurrency, { max: 10, fallback: "IQD" }) || "IQD";
  const salaryMin = toNonNegativeNumber(body.salaryMin);
  const salaryMax = toNonNegativeNumber(body.salaryMax);
  const salaryIsNegotiable = toBool(body.salaryIsNegotiable, true);
  const yearsExperienceMin = body.yearsExperienceMin == null
    ? null
    : toPositiveInt(body.yearsExperienceMin, { min: 0, max: 80 });
  const yearsExperienceMax = body.yearsExperienceMax == null
    ? null
    : toPositiveInt(body.yearsExperienceMax, { min: 0, max: 80 });
  const vacancies = toPositiveInt(body.vacancies, { min: 1, max: 999 }) || 1;
  const expiresAt = toIsoDate(body.expiresAt);
  const merchantId = body.merchantId == null
    ? null
    : toPositiveInt(body.merchantId, { min: 1, max: Number.MAX_SAFE_INTEGER });
  const status = normalizeEnum(body.status, jobStatuses, "active");
  const isFeatured = toBool(body.isFeatured, false);

  if (!title) errors.push("title");
  if (!category) errors.push("category");
  if (activityType == null) errors.push("activityType");
  if (department == null) errors.push("department");
  if (
    activityType != null &&
    department != null &&
    !isDepartmentAllowedForActivity(activityType, department)
  ) {
    errors.push("activityDepartment");
  }
  if (!city) errors.push("city");
  if (!description) errors.push("description");
  if (workplaceType == null) errors.push("workplaceType");
  if (employmentType == null) errors.push("employmentType");
  if (experienceLevel == null) errors.push("experienceLevel");
  if (salaryPeriod == null) errors.push("salaryPeriod");
  if (status == null) errors.push("status");
  if (
    salaryMin != null &&
    salaryMax != null &&
    Number.isFinite(salaryMin) &&
    Number.isFinite(salaryMax) &&
    salaryMax < salaryMin
  ) {
    errors.push("salaryRange");
  }
  if (
    yearsExperienceMin != null &&
    yearsExperienceMax != null &&
    yearsExperienceMax < yearsExperienceMin
  ) {
    errors.push("experienceRange");
  }
  if (body.expiresAt != null && !expiresAt) errors.push("expiresAt");
  if (body.merchantId != null && merchantId == null) errors.push("merchantId");

  if (errors.length > 0) return { ok: false, errors };

  return {
    ok: true,
    value: {
      title,
      companyName,
      companyLogoUrl,
      category,
      activityType,
      department,
      city,
      area,
      workplaceType: workplaceType || "on_site",
      employmentType: employmentType || "full_time",
      experienceLevel: experienceLevel || "mid",
      educationLevel,
      salaryMin,
      salaryMax,
      salaryCurrency,
      salaryPeriod: salaryPeriod || "monthly",
      salaryIsNegotiable,
      yearsExperienceMin,
      yearsExperienceMax,
      vacancies,
      description,
      requirements,
      responsibilities,
      benefits,
      skills,
      contactPhone,
      contactEmail,
      applyUrl,
      expiresAt,
      merchantId,
      status: status || "active",
      isFeatured,
    },
  };
}

export function validateUpdateJobBody(body = {}) {
  const errors = [];
  const value = {};

  if (body.title !== undefined) {
    const title = toTrimmedString(body.title, { max: 180, fallback: "" });
    if (!title) errors.push("title");
    else value.title = title;
  }

  if (body.companyName !== undefined) {
    value.companyName = toNullableString(body.companyName, { max: 180 });
  }
  if (body.companyLogoUrl !== undefined) {
    value.companyLogoUrl = toNullableString(body.companyLogoUrl, { max: 1200 });
  }
  if (body.category !== undefined) {
    const category = toTrimmedString(body.category, { max: 120, fallback: "" });
    if (!category) errors.push("category");
    else value.category = category;
  }
  if (body.activityType !== undefined) {
    const activityType = normalizeActivityType(body.activityType, null);
    if (activityType == null) errors.push("activityType");
    else value.activityType = activityType;
  }
  if (body.department !== undefined) {
    const department = normalizeDepartment(body.department, null);
    if (department == null) errors.push("department");
    else value.department = department;
  }
  if (body.city !== undefined) {
    const city = toTrimmedString(body.city, { max: 120, fallback: "" });
    if (!city) errors.push("city");
    else value.city = city;
  }
  if (body.area !== undefined) {
    value.area = toNullableString(body.area, { max: 120 });
  }
  if (body.description !== undefined) {
    const description = toTrimmedString(body.description, {
      max: 12000,
      fallback: "",
    });
    if (!description) errors.push("description");
    else value.description = description;
  }
  if (body.requirements !== undefined) {
    value.requirements = toNullableString(body.requirements, { max: 12000 });
  }
  if (body.responsibilities !== undefined) {
    value.responsibilities = toNullableString(body.responsibilities, {
      max: 12000,
    });
  }
  if (body.benefits !== undefined) {
    value.benefits = toNullableString(body.benefits, { max: 12000 });
  }
  if (body.skills !== undefined) {
    value.skills = splitSkills(body.skills);
  }
  if (body.contactPhone !== undefined) {
    value.contactPhone = toNullableString(body.contactPhone, { max: 30 });
  }
  if (body.contactEmail !== undefined) {
    value.contactEmail = toNullableString(body.contactEmail, { max: 180 });
  }
  if (body.applyUrl !== undefined) {
    value.applyUrl = toNullableString(body.applyUrl, { max: 1200 });
  }
  if (body.educationLevel !== undefined) {
    value.educationLevel = toNullableString(body.educationLevel, { max: 80 });
  }
  if (body.workplaceType !== undefined) {
    const workplaceType = normalizeEnum(body.workplaceType, workplaceTypes, null);
    if (workplaceType == null) errors.push("workplaceType");
    else value.workplaceType = workplaceType;
  }
  if (body.employmentType !== undefined) {
    const employmentType = normalizeEnum(
      body.employmentType,
      employmentTypes,
      null
    );
    if (employmentType == null) errors.push("employmentType");
    else value.employmentType = employmentType;
  }
  if (body.experienceLevel !== undefined) {
    const experienceLevel = normalizeEnum(
      body.experienceLevel,
      experienceLevels,
      null
    );
    if (experienceLevel == null) errors.push("experienceLevel");
    else value.experienceLevel = experienceLevel;
  }
  if (body.salaryPeriod !== undefined) {
    const salaryPeriod = normalizeEnum(body.salaryPeriod, salaryPeriods, null);
    if (salaryPeriod == null) errors.push("salaryPeriod");
    else value.salaryPeriod = salaryPeriod;
  }
  if (body.salaryCurrency !== undefined) {
    const salaryCurrency = toTrimmedString(body.salaryCurrency, {
      max: 10,
      fallback: "",
    });
    if (!salaryCurrency) errors.push("salaryCurrency");
    else value.salaryCurrency = salaryCurrency;
  }
  if (body.salaryMin !== undefined) {
    const salaryMin = toNonNegativeNumber(body.salaryMin);
    if (salaryMin == null && body.salaryMin !== null && body.salaryMin !== "") {
      errors.push("salaryMin");
    } else {
      value.salaryMin = salaryMin;
    }
  }
  if (body.salaryMax !== undefined) {
    const salaryMax = toNonNegativeNumber(body.salaryMax);
    if (salaryMax == null && body.salaryMax !== null && body.salaryMax !== "") {
      errors.push("salaryMax");
    } else {
      value.salaryMax = salaryMax;
    }
  }
  if (body.salaryIsNegotiable !== undefined) {
    value.salaryIsNegotiable = toBool(body.salaryIsNegotiable, true);
  }
  if (body.yearsExperienceMin !== undefined) {
    const yearsExperienceMin = body.yearsExperienceMin == null
      ? null
      : toPositiveInt(body.yearsExperienceMin, { min: 0, max: 80 });
    if (
      yearsExperienceMin == null &&
      body.yearsExperienceMin !== null &&
      body.yearsExperienceMin !== ""
    ) {
      errors.push("yearsExperienceMin");
    } else {
      value.yearsExperienceMin = yearsExperienceMin;
    }
  }
  if (body.yearsExperienceMax !== undefined) {
    const yearsExperienceMax = body.yearsExperienceMax == null
      ? null
      : toPositiveInt(body.yearsExperienceMax, { min: 0, max: 80 });
    if (
      yearsExperienceMax == null &&
      body.yearsExperienceMax !== null &&
      body.yearsExperienceMax !== ""
    ) {
      errors.push("yearsExperienceMax");
    } else {
      value.yearsExperienceMax = yearsExperienceMax;
    }
  }
  if (body.vacancies !== undefined) {
    const vacancies = toPositiveInt(body.vacancies, { min: 1, max: 999 });
    if (!vacancies) errors.push("vacancies");
    else value.vacancies = vacancies;
  }
  if (body.expiresAt !== undefined) {
    const expiresAt = toIsoDate(body.expiresAt);
    if (body.expiresAt != null && body.expiresAt !== "" && !expiresAt) {
      errors.push("expiresAt");
    } else {
      value.expiresAt = expiresAt;
    }
  }
  if (body.merchantId !== undefined) {
    const merchantId = body.merchantId == null
      ? null
      : toPositiveInt(body.merchantId, {
          min: 1,
          max: Number.MAX_SAFE_INTEGER,
        });
    if (merchantId == null && body.merchantId != null) errors.push("merchantId");
    else value.merchantId = merchantId;
  }
  if (body.isFeatured !== undefined) {
    value.isFeatured = toBool(body.isFeatured, false);
  }

  if (
    value.salaryMin != null &&
    value.salaryMax != null &&
    value.salaryMax < value.salaryMin
  ) {
    errors.push("salaryRange");
  }
  if (
    value.yearsExperienceMin != null &&
    value.yearsExperienceMax != null &&
    value.yearsExperienceMax < value.yearsExperienceMin
  ) {
    errors.push("experienceRange");
  }
  if (
    value.activityType != null &&
    value.department != null &&
    !isDepartmentAllowedForActivity(value.activityType, value.department)
  ) {
    errors.push("activityDepartment");
  }

  if (Object.keys(value).length === 0) {
    errors.push("body");
  }

  if (errors.length > 0) return { ok: false, errors };
  return { ok: true, value };
}

export function validateUpdateJobStatusBody(body = {}) {
  const status = normalizeEnum(body.status, jobStatuses, null);
  if (!status) {
    return { ok: false, errors: ["status"] };
  }
  return { ok: true, value: { status } };
}

export function validateApplyToJobBody(body = {}) {
  const errors = [];
  const message = toNullableString(body.message, { max: 3000 });
  const phone = toNullableString(body.phone, { max: 30 });
  const rawEmail = body.email ?? body.applicantEmail;
  const email = toNullableEmail(rawEmail);
  const resumeUrl = toNullableString(body.resumeUrl, { max: 1200 });
  const expectedSalary = toNonNegativeNumber(body.expectedSalary);

  if (
    rawEmail != null &&
    String(rawEmail).trim().length > 0 &&
    email == null
  ) {
    errors.push("email");
  }
  if (body.expectedSalary !== undefined && body.expectedSalary !== null) {
    if (expectedSalary == null) errors.push("expectedSalary");
  }

  if (errors.length > 0) return { ok: false, errors };
  return {
    ok: true,
    value: {
      message,
      phone,
      email,
      resumeUrl,
      expectedSalary,
    },
  };
}

export function validateListJobApplicationsQuery(query = {}) {
  const page = toPositiveInt(query.page, { min: 1, max: 100000 }) || 1;
  const limit = toPositiveInt(query.limit, { min: 1, max: 100 }) || 30;
  const status = query.status == null
    ? null
    : normalizeEnum(query.status, applicationStatuses, null);
  if (query.status != null && status == null) {
    return { ok: false, errors: ["status"] };
  }

  return {
    ok: true,
    value: { page, limit, status },
  };
}

export function validateUpdateApplicationStatusBody(body = {}) {
  const status = normalizeEnum(body.status, applicationStatuses, null);
  const reason = toNullableString(body.reason, { max: 1400 });
  const offerSalary = toNonNegativeNumber(body.offerSalary);
  const offerWorkHours = toNullableString(body.offerWorkHours, { max: 180 });
  const offerWorkDays = toNullableString(body.offerWorkDays, { max: 180 });
  const offerMessage = toNullableString(body.offerMessage, { max: 2400 });
  if (!status) {
    return { ok: false, errors: ["status"] };
  }
  if (
    [
      "shortlisted",
      "rejected",
      "hired",
      "withdrawn",
      "dismissed_after_hire",
      "archived",
    ].includes(status) &&
    (!reason || reason.trim().length < 2)
  ) {
    return { ok: false, errors: ["reason"] };
  }
  if (body.offerSalary !== undefined && body.offerSalary !== null) {
    if (offerSalary == null) {
      return { ok: false, errors: ["offerSalary"] };
    }
  }
  return {
    ok: true,
    value: {
      status,
      reason,
      offerSalary,
      offerWorkHours,
      offerWorkDays,
      offerMessage,
    },
  };
}

export function validateWithdrawMyApplicationBody(body = {}) {
  const reason = toNullableString(body.reason, { max: 1400 });
  if (!reason || reason.trim().length < 2) {
    return { ok: false, errors: ["reason"] };
  }
  return {
    ok: true,
    value: {
      reason,
    },
  };
}

export function validateListManagerApplicationsQuery(query = {}) {
  const errors = [];
  const page = toPositiveInt(query.page, { min: 1, max: 100000 }) || 1;
  const limit = toPositiveInt(query.limit, { min: 1, max: 100 }) || 30;
  const status = query.status == null
    ? null
    : normalizeEnum(query.status, applicationStatuses, null);
  const search = toNullableString(query.search, { max: 120 });
  const category = toNullableString(query.category, { max: 120 });
  const activityType = normalizeActivityType(query.activityType, null);
  const department = normalizeDepartment(query.department, null);
  const jobId = query.jobId == null
    ? null
    : toPositiveInt(query.jobId, { min: 1, max: Number.MAX_SAFE_INTEGER });

  if (query.status != null && status == null) errors.push("status");
  if (query.activityType != null && activityType == null) {
    errors.push("activityType");
  }
  if (query.department != null && department == null) {
    errors.push("department");
  }
  if (query.jobId != null && jobId == null) errors.push("jobId");
  if (
    activityType != null &&
    department != null &&
    !isDepartmentAllowedForActivity(activityType, department)
  ) {
    errors.push("activityDepartment");
  }

  if (errors.length > 0) return { ok: false, errors };
  return {
    ok: true,
    value: {
      page,
      limit,
      status,
      search,
      category,
      activityType,
      department,
      jobId,
    },
  };
}

export function validateListTalentPoolQuery(query = {}) {
  const base = validateListManagerApplicationsQuery(query);
  if (!base.ok) return base;
  return {
    ok: true,
    value: {
      status: base.value.status,
      search: base.value.search,
      category: base.value.category,
      activityType: base.value.activityType,
      department: base.value.department,
      jobId: base.value.jobId,
    },
  };
}

export function validateListRecommendationCandidatesQuery(query = {}) {
  const errors = [];
  const search = toNullableString(query.search, { max: 120 });
  const limit = toPositiveInt(query.limit, { min: 1, max: 120 }) || 40;

  if (query.limit != null && (Number(query.limit) < 1 || Number(query.limit) > 120)) {
    errors.push("limit");
  }

  if (errors.length > 0) return { ok: false, errors };
  return {
    ok: true,
    value: {
      search,
      limit,
    },
  };
}

export function validateCreateRecommendationBody(body = {}) {
  const errors = [];

  const sourceApplicationId =
    body.sourceApplicationId == null
      ? null
      : toPositiveInt(body.sourceApplicationId, {
          min: 1,
          max: Number.MAX_SAFE_INTEGER,
        });
  const candidateUserId =
    body.candidateUserId == null
      ? null
      : toPositiveInt(body.candidateUserId, {
          min: 1,
          max: Number.MAX_SAFE_INTEGER,
        });
  const candidateFullName = toNullableString(body.candidateFullName, {
    max: 180,
  });
  const candidatePhone = toNullableString(body.candidatePhone, { max: 30 });
  const rawCandidateEmail = body.candidateEmail;
  const candidateEmail = toNullableEmail(rawCandidateEmail);
  const candidateWorkTitle = toNullableString(body.candidateWorkTitle, {
    max: 160,
  });
  const candidateWorkCompany = toNullableString(body.candidateWorkCompany, {
    max: 180,
  });
  const note = toNullableString(body.note, { max: 1400 });

  if (body.sourceApplicationId != null && sourceApplicationId == null) {
    errors.push("sourceApplicationId");
  }
  if (body.candidateUserId != null && candidateUserId == null) {
    errors.push("candidateUserId");
  }
  if (
    rawCandidateEmail != null &&
    String(rawCandidateEmail).trim().length > 0 &&
    candidateEmail == null
  ) {
    errors.push("candidateEmail");
  }

  if (sourceApplicationId == null && candidateUserId == null && !candidateFullName) {
    errors.push("candidateFullName");
  }

  if (errors.length > 0) return { ok: false, errors };
  return {
    ok: true,
    value: {
      sourceApplicationId,
      candidateUserId,
      candidateFullName,
      candidatePhone,
      candidateEmail,
      candidateWorkTitle,
      candidateWorkCompany,
      note,
    },
  };
}

export function validateAcceptRecommendationBody(body = {}) {
  const reason = toNullableString(body.reason, { max: 1400 });
  return {
    ok: true,
    value: {
      reason,
    },
  };
}

export function getJobsTaxonomyMeta() {
  return {
    activityTypes: [...JOB_ACTIVITY_TYPES],
    departmentsByActivity: { ...JOB_DEPARTMENTS_BY_ACTIVITY },
  };
}
