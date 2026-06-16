import { q } from "../../config/db.js";

function jobApplicationHistoryJsonSql(alias = "a") {
  return `COALESCE((
    SELECT json_agg(
      json_build_object(
        'id', h.id,
        'applicationId', h.application_id,
        'jobId', h.job_id,
        'previousStatus', h.previous_status,
        'nextStatus', h.next_status,
        'reason', h.reason,
        'changedByUserId', h.changed_by_user_id,
        'changedByName', actor.full_name,
        'changedByRole', actor.role,
        'changedAt', h.changed_at
      )
      ORDER BY h.changed_at DESC, h.id DESC
    )
    FROM job_application_status_history h
    LEFT JOIN app_user actor ON actor.id = h.changed_by_user_id
    WHERE h.application_id = ${alias}.id
  ), '[]'::json)`;
}

export async function findOwnerMerchantByUserId(ownerUserId) {
  const r = await q(
    `SELECT id, name, image_url, is_approved
     FROM merchant
     WHERE owner_user_id = $1
     LIMIT 1`,
    [Number(ownerUserId)]
  );
  return r.rows[0] || null;
}

export async function findHrMerchantByUserId(hrUserId) {
  const r = await q(
    `SELECT m.id, m.name, m.image_url, m.is_approved
     FROM merchant_hr_staff hs
     JOIN merchant m ON m.id = hs.merchant_id
     WHERE hs.hr_user_id = $1
       AND hs.is_active = TRUE
     ORDER BY hs.updated_at DESC, hs.created_at DESC
     LIMIT 1`,
    [Number(hrUserId)]
  );
  return r.rows[0] || null;
}

export async function findMerchantById(merchantId) {
  const r = await q(
    `SELECT id, name, image_url, owner_user_id, is_approved
     FROM merchant
     WHERE id = $1
     LIMIT 1`,
    [Number(merchantId)]
  );
  return r.rows[0] || null;
}

export async function createJob(dto) {
  const r = await q(
    `INSERT INTO job_post
      (
        title,
        company_name,
        company_logo_url,
        category,
        activity_type,
        department,
        city,
        area,
        workplace_type,
        employment_type,
        experience_level,
        education_level,
        salary_min,
        salary_max,
        salary_currency,
        salary_period,
        salary_is_negotiable,
        years_experience_min,
        years_experience_max,
        vacancies,
        description,
        requirements,
        responsibilities,
        benefits,
        skills,
        contact_phone,
        contact_email,
        apply_url,
        status,
        is_featured,
        expires_at,
        created_by_user_id,
        created_by_role,
        merchant_id
      )
     VALUES
      (
        $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,
        $21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32,$33,$34
      )
     RETURNING *`,
    [
      dto.title,
      dto.companyName,
      dto.companyLogoUrl,
      dto.category,
      dto.activityType,
      dto.department,
      dto.city,
      dto.area,
      dto.workplaceType,
      dto.employmentType,
      dto.experienceLevel,
      dto.educationLevel,
      dto.salaryMin,
      dto.salaryMax,
      dto.salaryCurrency,
      dto.salaryPeriod,
      dto.salaryIsNegotiable,
      dto.yearsExperienceMin,
      dto.yearsExperienceMax,
      dto.vacancies,
      dto.description,
      dto.requirements,
      dto.responsibilities,
      dto.benefits,
      dto.skills || [],
      dto.contactPhone,
      dto.contactEmail,
      dto.applyUrl,
      dto.status,
      dto.isFeatured,
      dto.expiresAt,
      Number(dto.createdByUserId),
      dto.createdByRole,
      dto.merchantId,
    ]
  );
  return r.rows[0] || null;
}

export async function updateJob(jobId, patch) {
  const map = {
    title: "title",
    companyName: "company_name",
    companyLogoUrl: "company_logo_url",
    category: "category",
    activityType: "activity_type",
    department: "department",
    city: "city",
    area: "area",
    workplaceType: "workplace_type",
    employmentType: "employment_type",
    experienceLevel: "experience_level",
    educationLevel: "education_level",
    salaryMin: "salary_min",
    salaryMax: "salary_max",
    salaryCurrency: "salary_currency",
    salaryPeriod: "salary_period",
    salaryIsNegotiable: "salary_is_negotiable",
    yearsExperienceMin: "years_experience_min",
    yearsExperienceMax: "years_experience_max",
    vacancies: "vacancies",
    description: "description",
    requirements: "requirements",
    responsibilities: "responsibilities",
    benefits: "benefits",
    skills: "skills",
    contactPhone: "contact_phone",
    contactEmail: "contact_email",
    applyUrl: "apply_url",
    status: "status",
    isFeatured: "is_featured",
    expiresAt: "expires_at",
    merchantId: "merchant_id",
  };

  const sets = [];
  const values = [];
  let idx = 1;

  for (const [key, column] of Object.entries(map)) {
    if (patch[key] === undefined) continue;
    sets.push(`${column} = $${idx++}`);
    values.push(patch[key]);
  }

  if (sets.length === 0) {
    return findJobById(jobId);
  }

  values.push(Number(jobId));
  const r = await q(
    `UPDATE job_post
     SET ${sets.join(", ")}
     WHERE id = $${idx}
       AND deleted_at IS NULL
     RETURNING *`,
    values
  );
  return r.rows[0] || null;
}

export async function softDeleteJob(jobId) {
  const r = await q(
    `UPDATE job_post
     SET deleted_at = NOW(),
         status = 'closed'
     WHERE id = $1
       AND deleted_at IS NULL
     RETURNING id`,
    [Number(jobId)]
  );
  return r.rows[0] || null;
}

export async function findJobById(jobId, { viewerUserId = null } = {}) {
  const normalizedViewerId = Number(viewerUserId) || 0;
  const r = await q(
    `SELECT
       j.*,
       u.full_name AS creator_full_name,
       u.phone AS creator_phone,
       u.image_url AS creator_image_url,
       m.name AS merchant_name,
       m.image_url AS merchant_image_url,
       EXISTS (
         SELECT 1
         FROM job_application a
         WHERE a.job_id = j.id
           AND a.applicant_user_id = $2
       ) AS has_applied,
       (
         SELECT COUNT(*)::INT
         FROM job_application a
         WHERE a.job_id = j.id
       ) AS applications_count,
       EXISTS (
         SELECT 1
         FROM job_application a_hired
         WHERE a_hired.job_id = j.id
           AND a_hired.status = 'hired'
       ) AS has_hired_application
     FROM job_post j
     LEFT JOIN app_user u ON u.id = j.created_by_user_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     WHERE j.id = $1
       AND j.deleted_at IS NULL
     LIMIT 1`,
    [Number(jobId), normalizedViewerId]
  );
  return r.rows[0] || null;
}

function pushFilterCondition({ conditions, params, expression, value }) {
  params.push(value);
  conditions.push(`${expression} $${params.length}`);
}

function buildJobFilters(query = {}, { onlyOpenDefault = true } = {}) {
  const conditions = ["j.deleted_at IS NULL"];
  const params = [];
  const onlyOpen = query.onlyOpen ?? onlyOpenDefault;

  if (onlyOpen) {
    conditions.push(`j.status = 'active'`);
    conditions.push(`(j.expires_at IS NULL OR j.expires_at >= NOW())`);
  }

  if (query.search) {
    params.push(`%${query.search}%`);
    const searchParam = `$${params.length}`;
    conditions.push(
      "(" +
        [
          `j.title ILIKE ${searchParam}`,
          `j.company_name ILIKE ${searchParam}`,
          `j.category ILIKE ${searchParam}`,
          `j.city ILIKE ${searchParam}`,
          `COALESCE(j.area, '') ILIKE ${searchParam}`,
          `j.description ILIKE ${searchParam}`,
        ].join(" OR ") +
        ")"
    );
  }

  if (query.category) {
    pushFilterCondition({
      conditions,
      params,
      expression: "j.category =",
      value: query.category,
    });
  }
  if (query.activityType) {
    pushFilterCondition({
      conditions,
      params,
      expression: "j.activity_type =",
      value: query.activityType,
    });
  }
  if (query.department) {
    pushFilterCondition({
      conditions,
      params,
      expression: "j.department =",
      value: query.department,
    });
  }
  if (query.city) {
    pushFilterCondition({
      conditions,
      params,
      expression: "j.city =",
      value: query.city,
    });
  }
  if (query.area) {
    pushFilterCondition({
      conditions,
      params,
      expression: "j.area =",
      value: query.area,
    });
  }
  if (query.employmentType) {
    pushFilterCondition({
      conditions,
      params,
      expression: "j.employment_type =",
      value: query.employmentType,
    });
  }
  if (query.workplaceType) {
    pushFilterCondition({
      conditions,
      params,
      expression: "j.workplace_type =",
      value: query.workplaceType,
    });
  }
  if (query.experienceLevel) {
    pushFilterCondition({
      conditions,
      params,
      expression: "j.experience_level =",
      value: query.experienceLevel,
    });
  }
  if (query.minSalary != null) {
    pushFilterCondition({
      conditions,
      params,
      expression: "COALESCE(j.salary_max, j.salary_min, 0) >=",
      value: Number(query.minSalary),
    });
  }
  if (query.maxSalary != null) {
    pushFilterCondition({
      conditions,
      params,
      expression: "COALESCE(j.salary_min, j.salary_max, 0) <=",
      value: Number(query.maxSalary),
    });
  }

  return { conditions, params };
}

function resolveSort(sort) {
  switch (sort) {
    case "salary_high":
      return "COALESCE(j.salary_max, j.salary_min, 0) DESC NULLS LAST, j.published_at DESC, j.id DESC";
    case "salary_low":
      return "COALESCE(j.salary_min, j.salary_max, 0) ASC NULLS LAST, j.published_at DESC, j.id DESC";
    case "expires_soon":
      return "j.expires_at ASC NULLS LAST, j.published_at DESC, j.id DESC";
    case "recent":
    default:
      return "j.is_featured DESC, j.published_at DESC, j.id DESC";
  }
}

export async function listJobs({
  viewerUserId,
  query,
  page = 1,
  limit = 20,
}) {
  const normalizedViewerId = Number(viewerUserId) || 0;
  const offset = (Math.max(1, page) - 1) * Math.max(1, limit);
  const filters = buildJobFilters(query, { onlyOpenDefault: true });
  const orderBy = resolveSort(query.sort);

  const countResult = await q(
    `SELECT COUNT(*)::INT AS total
     FROM job_post j
     WHERE ${filters.conditions.join(" AND ")}`,
    filters.params
  );
  const total = Number(countResult.rows[0]?.total || 0);

  const params = [...filters.params, normalizedViewerId, limit, offset];
  const viewerParamIndex = filters.params.length + 1;
  const limitParamIndex = filters.params.length + 2;
  const offsetParamIndex = filters.params.length + 3;

  const rows = await q(
    `SELECT
       j.*,
       u.full_name AS creator_full_name,
       u.phone AS creator_phone,
       u.image_url AS creator_image_url,
       m.name AS merchant_name,
       m.image_url AS merchant_image_url,
       EXISTS (
         SELECT 1
         FROM job_application a
         WHERE a.job_id = j.id
           AND a.applicant_user_id = $${viewerParamIndex}
       ) AS has_applied,
       (
         SELECT COUNT(*)::INT
         FROM job_application a
         WHERE a.job_id = j.id
       ) AS applications_count,
       EXISTS (
         SELECT 1
         FROM job_application a_hired
         WHERE a_hired.job_id = j.id
           AND a_hired.status = 'hired'
       ) AS has_hired_application
     FROM job_post j
     LEFT JOIN app_user u ON u.id = j.created_by_user_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     WHERE ${filters.conditions.join(" AND ")}
     ORDER BY ${orderBy}
     LIMIT $${limitParamIndex}
     OFFSET $${offsetParamIndex}`,
    params
  );

  return {
    items: rows.rows,
    total,
    page,
    limit,
  };
}

export async function listManagedJobs({
  viewerUserId,
  actorRole,
  actorUserId = null,
  ownerMerchantId = null,
  publisherOnly = false,
  query,
  page = 1,
  limit = 20,
}) {
  const normalizedViewerId = Number(viewerUserId) || 0;
  const offset = (Math.max(1, page) - 1) * Math.max(1, limit);
  const filters = buildJobFilters(query, { onlyOpenDefault: false });

  if (actorRole === "owner" || actorRole === "hr") {
    filters.params.push(Number(ownerMerchantId || 0));
    filters.conditions.push(`j.merchant_id = $${filters.params.length}`);
  } else if (publisherOnly) {
    filters.params.push(Number(actorUserId || 0));
    filters.conditions.push(`j.created_by_user_id = $${filters.params.length}`);
  }

  const statusFilter = query.status || null;
  if (statusFilter) {
    filters.params.push(statusFilter);
    filters.conditions.push(`j.status = $${filters.params.length}`);
  }

  const countResult = await q(
    `SELECT COUNT(*)::INT AS total
     FROM job_post j
     WHERE ${filters.conditions.join(" AND ")}`,
    filters.params
  );
  const total = Number(countResult.rows[0]?.total || 0);

  const params = [...filters.params, normalizedViewerId, limit, offset];
  const viewerParamIndex = filters.params.length + 1;
  const limitParamIndex = filters.params.length + 2;
  const offsetParamIndex = filters.params.length + 3;

  const rows = await q(
    `SELECT
       j.*,
       u.full_name AS creator_full_name,
       u.phone AS creator_phone,
       u.image_url AS creator_image_url,
       m.name AS merchant_name,
       m.image_url AS merchant_image_url,
       EXISTS (
         SELECT 1
         FROM job_application a
         WHERE a.job_id = j.id
           AND a.applicant_user_id = $${viewerParamIndex}
       ) AS has_applied,
       (
         SELECT COUNT(*)::INT
         FROM job_application a
         WHERE a.job_id = j.id
       ) AS applications_count,
       EXISTS (
         SELECT 1
         FROM job_application a_hired
         WHERE a_hired.job_id = j.id
           AND a_hired.status = 'hired'
       ) AS has_hired_application
     FROM job_post j
     LEFT JOIN app_user u ON u.id = j.created_by_user_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     WHERE ${filters.conditions.join(" AND ")}
     ORDER BY j.updated_at DESC, j.id DESC
     LIMIT $${limitParamIndex}
     OFFSET $${offsetParamIndex}`,
    params
  );

  return {
    items: rows.rows,
    total,
    page,
    limit,
  };
}

export async function createJobApplication({
  jobId,
  applicantUserId,
  fullName,
  phone,
  email,
  message,
  resumeUrl,
  attachmentUrl,
  attachmentMime,
  attachmentName,
  expectedSalary,
}) {
  const r = await q(
    `INSERT INTO job_application
      (
        job_id,
        applicant_user_id,
        full_name,
        phone,
        applicant_email,
        message,
        resume_url,
        attachment_url,
        attachment_mime,
        attachment_name,
        expected_salary
      )
     VALUES
      ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
     RETURNING *`,
    [
      Number(jobId),
      Number(applicantUserId),
      fullName,
      phone,
      email,
      message,
      resumeUrl,
      attachmentUrl,
      attachmentMime,
      attachmentName,
      expectedSalary,
    ]
  );
  return r.rows[0] || null;
}

export async function listMyApplications({
  userId,
  page = 1,
  limit = 30,
  status = null,
}) {
  const offset = (Math.max(1, page) - 1) * Math.max(1, limit);
  const conditions = ["a.applicant_user_id = $1", "j.deleted_at IS NULL"];
  const params = [Number(userId)];

  if (status) {
    params.push(status);
    conditions.push(`a.status = $${params.length}`);
  }

  const countResult = await q(
    `SELECT COUNT(*)::INT AS total
     FROM job_application a
     JOIN job_post j ON j.id = a.job_id
     WHERE ${conditions.join(" AND ")}`,
    params
  );
  const total = Number(countResult.rows[0]?.total || 0);

  params.push(limit, offset);
  const rows = await q(
    `SELECT
       a.*,
       j.id AS job_id,
       j.title AS job_title,
       j.company_name AS job_company_name,
       j.company_logo_url AS job_company_logo_url,
       j.city AS job_city,
       j.area AS job_area,
       j.category AS job_category,
       j.activity_type AS job_activity_type,
       j.department AS job_department,
       j.employment_type AS job_employment_type,
       j.workplace_type AS job_workplace_type,
       j.experience_level AS job_experience_level,
       j.created_by_user_id AS job_created_by_user_id,
       j.merchant_id AS job_merchant_id,
       j.status AS job_status,
       j.expires_at AS job_expires_at,
       m.name AS job_merchant_name,
       m.type AS job_merchant_type,
       m.image_url AS job_merchant_image_url,
       ${jobApplicationHistoryJsonSql("a")} AS status_history
     FROM job_application a
     JOIN job_post j ON j.id = a.job_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     WHERE ${conditions.join(" AND ")}
     ORDER BY a.created_at DESC
     LIMIT $${params.length - 1}
     OFFSET $${params.length}`,
    params
  );

  return {
    items: rows.rows,
    total,
    page,
    limit,
  };
}

export async function listJobApplications({
  jobId,
  page = 1,
  limit = 30,
  status = null,
}) {
  const offset = (Math.max(1, page) - 1) * Math.max(1, limit);
  const conditions = ["a.job_id = $1"];
  const params = [Number(jobId)];
  if (status) {
    params.push(status);
    conditions.push(`a.status = $${params.length}`);
  }

  const countResult = await q(
    `SELECT COUNT(*)::INT AS total
     FROM job_application a
     WHERE ${conditions.join(" AND ")}`,
    params
  );
  const total = Number(countResult.rows[0]?.total || 0);

  params.push(limit, offset);
  const rows = await q(
    `SELECT
       a.*,
       u.full_name AS applicant_profile_full_name,
       u.phone AS applicant_profile_phone,
       u.block AS applicant_block,
       u.building_number AS applicant_building_number,
       u.apartment AS applicant_apartment,
       u.image_url AS applicant_image_url,
       j.title AS job_title,
       j.company_name AS job_company_name,
       j.created_by_user_id AS job_created_by_user_id,
       j.activity_type AS job_activity_type,
       j.department AS job_department,
       j.category AS job_category,
       j.merchant_id AS job_merchant_id,
       m.name AS job_merchant_name,
       m.type AS job_merchant_type,
       ${jobApplicationHistoryJsonSql("a")} AS status_history
     FROM job_application a
     JOIN app_user u ON u.id = a.applicant_user_id
     JOIN job_post j ON j.id = a.job_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     WHERE ${conditions.join(" AND ")}
     ORDER BY a.created_at DESC
     LIMIT $${params.length - 1}
     OFFSET $${params.length}`,
    params
  );

  return {
    items: rows.rows,
    total,
    page,
    limit,
  };
}

export async function updateJobApplicationStatus({
  jobId,
  applicationId,
  status,
  reason = null,
  actorUserId = null,
  offerSalary = null,
  offerWorkHours = null,
  offerWorkDays = null,
  offerMessage = null,
  offerAttachmentUrl = null,
  offerAttachmentMime = null,
  offerAttachmentName = null,
  offerSentByUserId = null,
}) {
  const isHiredStatus = String(status || "").toLowerCase() === "hired";
  const r = await q(
    `WITH updated AS (
       UPDATE job_application
       SET status = $1,
           status_reason = $2,
           status_changed_by_user_id = $3,
           status_changed_at = NOW(),
           offer_salary = CASE
             WHEN $6::boolean THEN $7::numeric
             ELSE offer_salary
           END,
           offer_work_hours = CASE
             WHEN $6::boolean THEN $8::text
             ELSE offer_work_hours
           END,
           offer_work_days = CASE
             WHEN $6::boolean THEN $9::text
             ELSE offer_work_days
           END,
           offer_message = CASE
             WHEN $6::boolean THEN $10::text
             ELSE offer_message
           END,
           offer_attachment_url = CASE
             WHEN $6::boolean THEN $11::text
             ELSE offer_attachment_url
           END,
           offer_attachment_mime = CASE
             WHEN $6::boolean THEN $12::text
             ELSE offer_attachment_mime
           END,
           offer_attachment_name = CASE
             WHEN $6::boolean THEN $13::text
             ELSE offer_attachment_name
           END,
           offer_sent_by_user_id = CASE
             WHEN $6::boolean THEN $14::bigint
             ELSE offer_sent_by_user_id
           END,
           offer_sent_at = CASE
             WHEN $6::boolean THEN NOW()
             ELSE offer_sent_at
           END,
           offer_accepted_at = offer_accepted_at,
           offer_acceptance_attachment_url = offer_acceptance_attachment_url,
           offer_acceptance_attachment_mime = offer_acceptance_attachment_mime,
           offer_acceptance_attachment_name = offer_acceptance_attachment_name
       WHERE id = $4
         AND job_id = $5
       RETURNING *
     )
     SELECT
       up.*,
       u.full_name AS applicant_profile_full_name,
       u.phone AS applicant_profile_phone,
       u.block AS applicant_block,
       u.building_number AS applicant_building_number,
       u.apartment AS applicant_apartment,
       u.image_url AS applicant_image_url,
       j.title AS job_title,
       j.company_name AS job_company_name,
       j.created_by_user_id AS job_created_by_user_id,
       j.activity_type AS job_activity_type,
       j.department AS job_department,
       j.category AS job_category,
       j.merchant_id AS job_merchant_id,
       m.name AS job_merchant_name,
       m.type AS job_merchant_type,
       ${jobApplicationHistoryJsonSql("up")} AS status_history
     FROM updated up
     JOIN app_user u ON u.id = up.applicant_user_id
     JOIN job_post j ON j.id = up.job_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     LIMIT 1`,
    [
      status,
      reason,
      actorUserId == null ? null : Number(actorUserId),
      Number(applicationId),
      Number(jobId),
      isHiredStatus,
      offerSalary == null ? null : Number(offerSalary),
      offerWorkHours,
      offerWorkDays,
      offerMessage,
      offerAttachmentUrl,
      offerAttachmentMime,
      offerAttachmentName,
      offerSentByUserId == null ? null : Number(offerSentByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function closeJobAfterHire(jobId) {
  const r = await q(
    `UPDATE job_post
     SET status = 'closed',
         updated_at = NOW()
     WHERE id = $1
       AND deleted_at IS NULL
     RETURNING id, status`,
    [Number(jobId)]
  );
  return r.rows[0] || null;
}

export async function findApplicationByIdForApplicant({
  applicationId,
  applicantUserId,
}) {
  const r = await q(
    `SELECT
       a.*,
       u.full_name AS applicant_profile_full_name,
       u.phone AS applicant_profile_phone,
       u.block AS applicant_block,
       u.building_number AS applicant_building_number,
       u.apartment AS applicant_apartment,
       u.image_url AS applicant_image_url,
       j.title AS job_title,
       j.company_name AS job_company_name,
       j.created_by_user_id AS job_created_by_user_id,
       j.activity_type AS job_activity_type,
       j.department AS job_department,
       j.category AS job_category,
       j.merchant_id AS job_merchant_id,
       m.name AS job_merchant_name,
       m.type AS job_merchant_type,
       ${jobApplicationHistoryJsonSql("a")} AS status_history
     FROM job_application a
     JOIN app_user u ON u.id = a.applicant_user_id
     JOIN job_post j ON j.id = a.job_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     WHERE a.id = $1
       AND a.applicant_user_id = $2
     LIMIT 1`,
    [Number(applicationId), Number(applicantUserId)]
  );
  return r.rows[0] || null;
}

export async function acceptJobOffer({
  applicationId,
  applicantUserId,
  acceptanceAttachmentUrl = null,
  acceptanceAttachmentMime = null,
  acceptanceAttachmentName = null,
}) {
  const r = await q(
    `WITH updated AS (
       UPDATE job_application
       SET offer_accepted_at = NOW(),
           offer_acceptance_attachment_url = $3,
           offer_acceptance_attachment_mime = $4,
           offer_acceptance_attachment_name = $5,
           updated_at = NOW()
       WHERE id = $1
         AND applicant_user_id = $2
         AND status = 'hired'
         AND offer_sent_at IS NOT NULL
       RETURNING id
     )
     SELECT
       a.*,
       u.full_name AS applicant_profile_full_name,
       u.phone AS applicant_profile_phone,
       u.block AS applicant_block,
       u.building_number AS applicant_building_number,
       u.apartment AS applicant_apartment,
       u.image_url AS applicant_image_url,
       j.title AS job_title,
       j.company_name AS job_company_name,
       j.created_by_user_id AS job_created_by_user_id,
       j.activity_type AS job_activity_type,
       j.department AS job_department,
       j.category AS job_category,
       j.merchant_id AS job_merchant_id,
       m.name AS job_merchant_name,
       m.type AS job_merchant_type,
       ${jobApplicationHistoryJsonSql("a")} AS status_history
     FROM updated up
     JOIN job_application a ON a.id = up.id
     JOIN app_user u ON u.id = a.applicant_user_id
     JOIN job_post j ON j.id = a.job_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     LIMIT 1`,
    [
      Number(applicationId),
      Number(applicantUserId),
      acceptanceAttachmentUrl,
      acceptanceAttachmentMime,
      acceptanceAttachmentName,
    ]
  );
  return r.rows[0] || null;
}

export async function updateApplicantWorkProfile({
  applicantUserId,
  workTitle = null,
  workCompany = null,
}) {
  const r = await q(
    `UPDATE app_user
     SET work_title = $2,
         work_company = $3
     WHERE id = $1
     RETURNING id, work_title, work_company`,
    [Number(applicantUserId), workTitle, workCompany]
  );
  return r.rows[0] || null;
}

export async function getJobFilterMeta() {
  const [categories, cities, areas] = await Promise.all([
    q(
      `SELECT DISTINCT category
       FROM job_post
       WHERE deleted_at IS NULL
         AND status = 'active'
         AND category IS NOT NULL
         AND TRIM(category) <> ''
       ORDER BY category ASC
       LIMIT 200`
    ),
    q(
      `SELECT DISTINCT city
       FROM job_post
       WHERE deleted_at IS NULL
         AND status = 'active'
         AND city IS NOT NULL
         AND TRIM(city) <> ''
       ORDER BY city ASC
       LIMIT 200`
    ),
    q(
      `SELECT DISTINCT area
       FROM job_post
       WHERE deleted_at IS NULL
         AND status = 'active'
         AND area IS NOT NULL
         AND TRIM(area) <> ''
       ORDER BY area ASC
       LIMIT 200`
    ),
  ]);

  return {
    categories: categories.rows.map((row) => row.category).filter(Boolean),
    cities: cities.rows.map((row) => row.city).filter(Boolean),
    areas: areas.rows.map((row) => row.area).filter(Boolean),
  };
}

export async function listJobApplicationManagerRecipients({
  jobId,
  excludeUserId = null,
}) {
  const params = [Number(jobId), Number(excludeUserId) || 0];
  const r = await q(
    `SELECT DISTINCT target.user_id
     FROM (
       SELECT j.created_by_user_id AS user_id
       FROM job_post j
       WHERE j.id = $1
         AND j.deleted_at IS NULL

       UNION ALL

       SELECT m.owner_user_id AS user_id
       FROM job_post j
       JOIN merchant m ON m.id = j.merchant_id
       WHERE j.id = $1
         AND j.deleted_at IS NULL

       UNION ALL

       SELECT hs.hr_user_id AS user_id
       FROM job_post j
       JOIN merchant_hr_staff hs ON hs.merchant_id = j.merchant_id
       WHERE j.id = $1
         AND j.deleted_at IS NULL
         AND hs.is_active = TRUE

       UNION ALL

       SELECT u.id AS user_id
       FROM app_user u
       WHERE (u.role = 'admin' OR u.is_super_admin = TRUE)
         AND COALESCE(u.is_account_disabled, FALSE) = FALSE
     ) target
     WHERE target.user_id IS NOT NULL
       AND target.user_id <> $2`,
    params
  );

  return r.rows
    .map((row) => Number(row.user_id || 0))
    .filter((id) => Number.isFinite(id) && id > 0);
}

function buildManagerApplicationsFilters({
  actorUserId = null,
  actorRole,
  ownerMerchantId = null,
  publisherOnly = false,
  query = {},
}) {
  const conditions = ["j.deleted_at IS NULL"];
  const params = [];

  if (actorRole === "owner" || actorRole === "hr") {
    params.push(Number(ownerMerchantId || 0));
    conditions.push(`j.merchant_id = $${params.length}`);
  } else if (publisherOnly) {
    params.push(Number(actorUserId || 0));
    conditions.push(`j.created_by_user_id = $${params.length}`);
  }

  if (query.jobId) {
    params.push(Number(query.jobId));
    conditions.push(`a.job_id = $${params.length}`);
  }
  if (query.status) {
    params.push(query.status);
    conditions.push(`a.status = $${params.length}`);
  }
  if (query.activityType) {
    params.push(query.activityType);
    conditions.push(`j.activity_type = $${params.length}`);
  }
  if (query.department) {
    params.push(query.department);
    conditions.push(`j.department = $${params.length}`);
  }
  if (query.category) {
    params.push(query.category);
    conditions.push(`j.category = $${params.length}`);
  }
  if (query.search) {
    params.push(`%${query.search}%`);
    const searchParam = `$${params.length}`;
    conditions.push(
      "(" +
        [
          `COALESCE(a.full_name, '') ILIKE ${searchParam}`,
          `COALESCE(a.phone, '') ILIKE ${searchParam}`,
          `COALESCE(a.applicant_email, '') ILIKE ${searchParam}`,
          `COALESCE(j.title, '') ILIKE ${searchParam}`,
          `COALESCE(j.company_name, '') ILIKE ${searchParam}`,
          `COALESCE(m.name, '') ILIKE ${searchParam}`,
        ].join(" OR ") +
        ")"
    );
  }

  return { conditions, params };
}

export async function listManagerApplications({
  actorUserId = null,
  actorRole,
  ownerMerchantId = null,
  publisherOnly = false,
  query = {},
  page = 1,
  limit = 30,
}) {
  const offset = (Math.max(1, page) - 1) * Math.max(1, limit);
  const filters = buildManagerApplicationsFilters({
    actorUserId,
    actorRole,
    ownerMerchantId,
    publisherOnly,
    query,
  });

  const countResult = await q(
    `SELECT COUNT(*)::INT AS total
     FROM job_application a
     JOIN job_post j ON j.id = a.job_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     WHERE ${filters.conditions.join(" AND ")}`,
    filters.params
  );
  const total = Number(countResult.rows[0]?.total || 0);

  const params = [...filters.params, limit, offset];
  const limitParam = filters.params.length + 1;
  const offsetParam = filters.params.length + 2;

  const rows = await q(
    `SELECT
       a.*,
       u.full_name AS applicant_profile_full_name,
       u.phone AS applicant_profile_phone,
       u.block AS applicant_block,
       u.building_number AS applicant_building_number,
       u.apartment AS applicant_apartment,
       u.image_url AS applicant_image_url,
       j.title AS job_title,
       j.company_name AS job_company_name,
       j.activity_type AS job_activity_type,
       j.department AS job_department,
       j.category AS job_category,
       j.created_by_user_id AS job_created_by_user_id,
       j.merchant_id AS job_merchant_id,
       m.name AS job_merchant_name,
       m.type AS job_merchant_type,
       ${jobApplicationHistoryJsonSql("a")} AS status_history
     FROM job_application a
     JOIN job_post j ON j.id = a.job_id
     JOIN app_user u ON u.id = a.applicant_user_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     WHERE ${filters.conditions.join(" AND ")}
     ORDER BY a.created_at DESC, a.id DESC
     LIMIT $${limitParam}
     OFFSET $${offsetParam}`,
    params
  );

  return {
    items: rows.rows,
    total,
    page,
    limit,
  };
}

export async function listTalentPoolGroups({
  actorUserId = null,
  actorRole,
  ownerMerchantId = null,
  publisherOnly = false,
  query = {},
}) {
  const filters = buildManagerApplicationsFilters({
    actorUserId,
    actorRole,
    ownerMerchantId,
    publisherOnly,
    query,
  });

  const rows = await q(
    `SELECT
       j.activity_type,
       j.department,
       COUNT(*)::INT AS total_applications,
       COUNT(DISTINCT a.applicant_user_id)::INT AS unique_applicants,
       COUNT(*) FILTER (WHERE a.status = 'submitted')::INT AS submitted_count,
       COUNT(*) FILTER (WHERE a.status = 'shortlisted')::INT AS shortlisted_count,
       COUNT(*) FILTER (WHERE a.status = 'rejected')::INT AS rejected_count,
       COUNT(*) FILTER (WHERE a.status = 'hired')::INT AS hired_count,
       COUNT(*) FILTER (WHERE a.status = 'withdrawn')::INT AS withdrawn_count,
       COUNT(*) FILTER (WHERE a.status = 'dismissed_after_hire')::INT AS dismissed_after_hire_count,
       COUNT(*) FILTER (WHERE a.status = 'archived')::INT AS archived_count,
       MAX(a.created_at) AS last_application_at
     FROM job_application a
     JOIN job_post j ON j.id = a.job_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     WHERE ${filters.conditions.join(" AND ")}
     GROUP BY j.activity_type, j.department
     ORDER BY j.activity_type ASC, j.department ASC`,
    filters.params
  );

  return rows.rows;
}

export async function findJobApplicationById(applicationId) {
  const r = await q(
    `SELECT
       a.*,
       u.full_name AS applicant_profile_full_name,
       u.phone AS applicant_profile_phone,
       u.image_url AS applicant_image_url,
       u.work_title AS applicant_work_title,
       u.work_company AS applicant_work_company,
       j.title AS job_title,
       j.company_name AS job_company_name,
       j.activity_type AS job_activity_type,
       j.department AS job_department,
       j.category AS job_category,
       j.created_by_user_id AS job_created_by_user_id,
       j.merchant_id AS job_merchant_id,
       m.name AS job_merchant_name,
       m.type AS job_merchant_type,
       ${jobApplicationHistoryJsonSql("a")} AS status_history
     FROM job_application a
     JOIN job_post j ON j.id = a.job_id
     LEFT JOIN app_user u ON u.id = a.applicant_user_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     WHERE a.id = $1
     LIMIT 1`,
    [Number(applicationId)]
  );
  return r.rows[0] || null;
}

export async function findJobApplicationByJobAndApplicant({
  jobId,
  applicantUserId,
}) {
  const r = await q(
    `SELECT
       a.*,
       u.full_name AS applicant_profile_full_name,
       u.phone AS applicant_profile_phone,
       u.block AS applicant_block,
       u.building_number AS applicant_building_number,
       u.apartment AS applicant_apartment,
       u.image_url AS applicant_image_url,
       j.title AS job_title,
       j.company_name AS job_company_name,
       j.created_by_user_id AS job_created_by_user_id,
       j.activity_type AS job_activity_type,
       j.department AS job_department,
       j.category AS job_category,
       j.merchant_id AS job_merchant_id,
       m.name AS job_merchant_name,
       m.type AS job_merchant_type
     FROM job_application a
     JOIN app_user u ON u.id = a.applicant_user_id
     JOIN job_post j ON j.id = a.job_id
     LEFT JOIN merchant m ON m.id = j.merchant_id
     WHERE a.job_id = $1
       AND a.applicant_user_id = $2
     LIMIT 1`,
    [Number(jobId), Number(applicantUserId)]
  );
  return r.rows[0] || null;
}

export async function findUserProfileById(userId) {
  const r = await q(
    `SELECT
       id,
       full_name,
       phone,
       image_url,
       work_title,
       work_company
     FROM app_user
     WHERE id = $1
     LIMIT 1`,
    [Number(userId)]
  );
  return r.rows[0] || null;
}

export async function listRecommendationCandidatesForJob({
  jobId,
  search = null,
  limit = 40,
}) {
  const safeLimit = Math.max(1, Math.min(120, Number(limit) || 40));
  const searchLike =
    typeof search === "string" && search.trim().length > 0
      ? `%${search.trim()}%`
      : null;
  const r = await q(
    `WITH target AS (
       SELECT
         j.id,
         j.activity_type,
         j.department,
         j.category
       FROM job_post j
       WHERE j.id = $1
         AND j.deleted_at IS NULL
       LIMIT 1
     ),
     pool AS (
       SELECT DISTINCT ON (a.applicant_user_id)
         a.id AS source_application_id,
         a.job_id AS source_job_id,
         a.applicant_user_id,
         COALESCE(u.full_name, a.full_name) AS candidate_full_name,
         COALESCE(u.phone, a.phone) AS candidate_phone,
         a.applicant_email AS candidate_email,
         u.image_url AS candidate_image_url,
         u.work_title AS candidate_work_title,
         u.work_company AS candidate_work_company,
         a.status AS source_status,
         a.created_at AS source_created_at,
         j.title AS source_job_title,
         j.company_name AS source_company_name,
         j.activity_type AS source_activity_type,
         j.department AS source_department,
         j.category AS source_category
       FROM target t
       JOIN job_application a ON TRUE
       JOIN job_post j ON j.id = a.job_id
       LEFT JOIN app_user u ON u.id = a.applicant_user_id
       WHERE j.deleted_at IS NULL
         AND a.applicant_user_id IS NOT NULL
         AND a.job_id <> t.id
         AND (
           j.activity_type = t.activity_type
           OR j.department = t.department
           OR j.category = t.category
         )
         AND (
           $2::text IS NULL
           OR COALESCE(u.full_name, a.full_name, '') ILIKE $2::text
           OR COALESCE(u.phone, a.phone, '') ILIKE $2::text
           OR COALESCE(a.applicant_email, '') ILIKE $2::text
           OR COALESCE(j.title, '') ILIKE $2::text
           OR COALESCE(j.company_name, '') ILIKE $2::text
         )
       ORDER BY a.applicant_user_id, a.created_at DESC
     )
     SELECT
       p.*,
       (
         SELECT COUNT(*)::INT
         FROM job_application aa
         WHERE aa.applicant_user_id = p.applicant_user_id
       ) AS applications_count
     FROM pool p
     ORDER BY p.source_created_at DESC
     LIMIT $3`,
    [Number(jobId), searchLike, safeLimit]
  );

  return r.rows;
}

export async function createJobRecommendation({
  jobId,
  recommendedByUserId,
  recommendedByRole,
  sourceApplicationId = null,
  candidateUserId = null,
  candidateFullName,
  candidatePhone = null,
  candidateEmail = null,
  candidateWorkTitle = null,
  candidateWorkCompany = null,
  recommendationNote = null,
  attachmentUrl = null,
  attachmentMime = null,
  attachmentName = null,
}) {
  const r = await q(
    `INSERT INTO job_recommendation
      (
        job_id,
        recommended_by_user_id,
        recommended_by_role,
        source_application_id,
        candidate_user_id,
        candidate_full_name,
        candidate_phone,
        candidate_email,
        candidate_work_title,
        candidate_work_company,
        recommendation_note,
        attachment_url,
        attachment_mime,
        attachment_name
      )
     VALUES
      ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
     RETURNING *`,
    [
      Number(jobId),
      Number(recommendedByUserId),
      String(recommendedByRole || "admin").trim().toLowerCase(),
      sourceApplicationId == null ? null : Number(sourceApplicationId),
      candidateUserId == null ? null : Number(candidateUserId),
      String(candidateFullName || "").trim(),
      candidatePhone,
      candidateEmail,
      candidateWorkTitle,
      candidateWorkCompany,
      recommendationNote,
      attachmentUrl,
      attachmentMime,
      attachmentName,
    ]
  );
  return r.rows[0] || null;
}

export async function listJobRecommendations({
  jobId,
  limit = 100,
}) {
  const safeLimit = Math.max(1, Math.min(300, Number(limit) || 100));
  const r = await q(
    `SELECT
       r.*,
       u.full_name AS recommender_full_name,
       u.phone AS recommender_phone,
       u.image_url AS recommender_image_url,
       c.image_url AS candidate_image_url,
       sa.job_id AS source_job_id,
       sa.status AS source_application_status,
       sa.created_at AS source_application_created_at,
       sa.message AS source_application_message,
       sa.resume_url AS source_resume_url,
       sa.attachment_url AS source_attachment_url,
       sa.attachment_mime AS source_attachment_mime,
       sa.attachment_name AS source_attachment_name,
       sa.expected_salary AS source_expected_salary,
       sa.applicant_email AS source_candidate_email,
       sa.phone AS source_candidate_phone,
       au.full_name AS source_candidate_full_name,
       au.image_url AS source_candidate_image_url,
       sj.title AS source_job_title,
       sj.company_name AS source_job_company_name,
       la.id AS linked_application_id,
       la.status AS linked_application_status,
       la.created_at AS linked_application_created_at,
       la.status_changed_at AS linked_application_status_changed_at
     FROM job_recommendation r
     LEFT JOIN app_user u ON u.id = r.recommended_by_user_id
     LEFT JOIN app_user c ON c.id = r.candidate_user_id
     LEFT JOIN job_application sa ON sa.id = r.source_application_id
     LEFT JOIN job_post sj ON sj.id = sa.job_id
     LEFT JOIN app_user au ON au.id = sa.applicant_user_id
     LEFT JOIN job_application la
       ON la.job_id = r.job_id
      AND la.applicant_user_id = r.candidate_user_id
     WHERE r.job_id = $1
     ORDER BY r.created_at DESC, r.id DESC
     LIMIT $2`,
    [Number(jobId), safeLimit]
  );
  return r.rows;
}

export async function findJobRecommendationById({
  jobId,
  recommendationId,
}) {
  const r = await q(
    `SELECT
       r.*,
       u.full_name AS recommender_full_name,
       u.phone AS recommender_phone,
       u.image_url AS recommender_image_url,
       c.image_url AS candidate_image_url,
       sa.job_id AS source_job_id,
       sa.status AS source_application_status,
       sa.created_at AS source_application_created_at,
       sa.message AS source_application_message,
       sa.resume_url AS source_resume_url,
       sa.attachment_url AS source_attachment_url,
       sa.attachment_mime AS source_attachment_mime,
       sa.attachment_name AS source_attachment_name,
       sa.expected_salary AS source_expected_salary,
       sa.applicant_email AS source_candidate_email,
       sa.phone AS source_candidate_phone,
       au.full_name AS source_candidate_full_name,
       au.image_url AS source_candidate_image_url,
       sj.title AS source_job_title,
       sj.company_name AS source_job_company_name,
       la.id AS linked_application_id,
       la.status AS linked_application_status,
       la.created_at AS linked_application_created_at,
       la.status_changed_at AS linked_application_status_changed_at
     FROM job_recommendation r
     LEFT JOIN app_user u ON u.id = r.recommended_by_user_id
     LEFT JOIN app_user c ON c.id = r.candidate_user_id
     LEFT JOIN job_application sa ON sa.id = r.source_application_id
     LEFT JOIN job_post sj ON sj.id = sa.job_id
     LEFT JOIN app_user au ON au.id = sa.applicant_user_id
     LEFT JOIN job_application la
       ON la.job_id = r.job_id
      AND la.applicant_user_id = r.candidate_user_id
     WHERE r.job_id = $1
       AND r.id = $2
     LIMIT 1`,
    [Number(jobId), Number(recommendationId)]
  );
  return r.rows[0] || null;
}
