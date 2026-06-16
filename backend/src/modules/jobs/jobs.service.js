import { AppError } from "../../shared/utils/errors.js";
import { getUserPublicById } from "../auth/auth.repo.js";
import { createManyNotifications } from "../notifications/notifications.repo.js";
import * as repo from "./jobs.repo.js";
import { getJobsTaxonomyMeta } from "./jobs.validators.js";

/**
 * Purpose:
 * منطق الوظائف المركزي: التصفح، إنشاء الوظائف، التقديم، مراجعة الطلبات،
 * والعروض الوظيفية والإشعارات المرتبطة بها.
 *
 * Used by:
 * - `jobs.controller.js`
 * - شاشات jobs/applications/HR management في Flutter
 */

function isAdminActor(actor) {
  return String(actor?.role || "").trim().toLowerCase() === "admin";
}

function isOwnerActor(actor) {
  return String(actor?.role || "").trim().toLowerCase() === "owner";
}

function isHrActor(actor) {
  return String(actor?.role || "").trim().toLowerCase() === "hr";
}

function isUserActor(actor) {
  return String(actor?.role || "").trim().toLowerCase() === "user";
}

function assertAuthedActor(actor) {
  const userId = Number(actor?.userId || 0);
  if (!Number.isFinite(userId) || userId <= 0) {
    throw new AppError("UNAUTHORIZED", { status: 401 });
  }
  return userId;
}

function resolveActorRoleForJobs(actor) {
  if (actor?.isSuperAdmin === true) return "admin";
  return normalizeRole(actor?.role);
}

async function assertCanManageJobs(actor) {
  assertAuthedActor(actor);
  if (
    actor?.isSuperAdmin === true ||
    isAdminActor(actor) ||
    isOwnerActor(actor) ||
    isHrActor(actor)
  ) {
    return;
  }
  throw new AppError("FORBIDDEN_JOB_MANAGEMENT", { status: 403 });
}

async function resolveOwnerMerchant(actor) {
  const ownerUserId = assertAuthedActor(actor);
  const merchant = await repo.findOwnerMerchantByUserId(ownerUserId);
  if (!merchant?.id) {
    throw new AppError("OWNER_MERCHANT_NOT_FOUND", { status: 404 });
  }
  return merchant;
}

async function resolveHrMerchant(actor) {
  const hrUserId = assertAuthedActor(actor);
  const merchant = await repo.findHrMerchantByUserId(hrUserId);
  if (!merchant?.id) {
    throw new AppError("HR_MERCHANT_NOT_FOUND", { status: 404 });
  }
  return merchant;
}

async function resolveManagerMerchant(actor) {
  if (isOwnerActor(actor)) return resolveOwnerMerchant(actor);
  if (isHrActor(actor)) return resolveHrMerchant(actor);
  return null;
}

function normalizeRole(role) {
  const normalized = String(role || "").trim().toLowerCase();
  return normalized || "user";
}

function assertAdminOrSuper(actor) {
  const userId = assertAuthedActor(actor);
  const role = normalizeRole(actor?.role);
  if (actor?.isSuperAdmin === true || role === "admin") {
    return { userId, role };
  }
  throw new AppError("FORBIDDEN_ADMIN_ONLY", { status: 403 });
}

function mapJob(row, actor = null) {
  if (!row) return null;

  const actorRole = normalizeRole(actor?.role);
  const actorUserId = Number(actor?.userId || 0);
  const actorIsSuperAdmin = actor?.isSuperAdmin === true;
  const actorManagedMerchantId = Number(
    actor?.managedMerchantId || actor?.merchantId || 0
  );
  const jobMerchantId = Number(row.merchant_id || 0);

  const canManageAsAdmin = actorRole === "admin";
  const isOwnJob = Number(row.created_by_user_id || 0) === actorUserId;
  const canManageAsManager =
    (actorRole === "owner" || actorRole === "hr") &&
    actorManagedMerchantId > 0 &&
    jobMerchantId > 0 &&
    actorManagedMerchantId === jobMerchantId;
  const canManage = canManageAsAdmin || canManageAsManager || isOwnJob;

  return {
    id: Number(row.id),
    title: row.title,
    companyName: row.company_name,
    companyLogoUrl: row.company_logo_url,
    category: row.category,
    activityType: row.activity_type ?? "general_business",
    department: row.department ?? "operations",
    city: row.city,
    area: row.area,
    workplaceType: row.workplace_type,
    employmentType: row.employment_type,
    experienceLevel: row.experience_level,
    educationLevel: row.education_level,
    salaryMin: row.salary_min == null ? null : Number(row.salary_min),
    salaryMax: row.salary_max == null ? null : Number(row.salary_max),
    salaryCurrency: row.salary_currency,
    salaryPeriod: row.salary_period,
    salaryIsNegotiable: row.salary_is_negotiable === true,
    yearsExperienceMin: row.years_experience_min,
    yearsExperienceMax: row.years_experience_max,
    vacancies: Number(row.vacancies || 0),
    description: row.description,
    requirements: row.requirements,
    responsibilities: row.responsibilities,
    benefits: row.benefits,
    skills: Array.isArray(row.skills) ? row.skills : [],
    contactPhone: row.contact_phone,
    contactEmail: row.contact_email,
    applyUrl: row.apply_url,
    status: row.status,
    isFeatured: row.is_featured === true,
    publishedAt: row.published_at,
    expiresAt: row.expires_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    createdByUserId: Number(row.created_by_user_id || 0),
    createdByRole: row.created_by_role,
    merchantId: row.merchant_id == null ? null : Number(row.merchant_id),
    merchantName: row.merchant_name ?? null,
    merchantImageUrl: row.merchant_image_url ?? null,
    creator: {
      fullName: row.creator_full_name ?? null,
      phone: row.creator_phone ?? null,
      imageUrl: row.creator_image_url ?? null,
    },
    hasApplied: row.has_applied === true,
    applicationsCount: Number(row.applications_count || 0),
    canManage: actorIsSuperAdmin || canManage,
  };
}

function mapApplication(row, actor = null) {
  if (!row) return null;
  const jobCreatedByUserId = Number(row.job_created_by_user_id || 0);
  const actorUserId = Number(actor?.userId || row.actor_user_id || 0);
  const actorRole = normalizeRole(actor?.role);
  const actorManagedMerchantId = Number(
    actor?.managedMerchantId || actor?.merchantId || 0
  );
  const jobMerchantId = Number(row.job_merchant_id || 0);
  const canManageAsAdmin =
    actor?.isSuperAdmin === true || actorRole === "admin";
  const canChangeStatus =
    canManageAsAdmin ||
    (jobCreatedByUserId > 0 &&
      actorUserId > 0 &&
      jobCreatedByUserId === actorUserId) ||
    ((actorRole === "owner" || actorRole === "hr") &&
      actorManagedMerchantId > 0 &&
      jobMerchantId > 0 &&
      actorManagedMerchantId === jobMerchantId);
  const canAcceptOffer =
    actorUserId > 0 &&
    Number(row.applicant_user_id || 0) === actorUserId &&
    String(row.status || "").toLowerCase() === "hired" &&
    row.offer_sent_at != null &&
    row.offer_accepted_at == null;
  return {
    id: Number(row.id),
    jobId: Number(row.job_id),
    applicantUserId: Number(row.applicant_user_id),
    fullName: row.full_name,
    phone: row.phone,
    submittedPhone: row.phone,
    profileFullName: row.applicant_profile_full_name ?? row.full_name ?? null,
    profilePhone: row.applicant_profile_phone ?? null,
    applicantEmail: row.applicant_email ?? null,
    message: row.message,
    resumeUrl: row.resume_url,
    attachmentUrl: row.attachment_url ?? null,
    attachmentMime: row.attachment_mime ?? null,
    attachmentName: row.attachment_name ?? null,
    expectedSalary:
      row.expected_salary == null ? null : Number(row.expected_salary),
    offerSalary: row.offer_salary == null ? null : Number(row.offer_salary),
    offerWorkHours: row.offer_work_hours ?? null,
    offerWorkDays: row.offer_work_days ?? null,
    offerMessage: row.offer_message ?? null,
    offerAttachmentUrl: row.offer_attachment_url ?? null,
    offerAttachmentMime: row.offer_attachment_mime ?? null,
    offerAttachmentName: row.offer_attachment_name ?? null,
    offerSentByUserId:
      row.offer_sent_by_user_id == null
        ? null
        : Number(row.offer_sent_by_user_id),
    offerSentAt: row.offer_sent_at ?? null,
    offerAcceptedAt: row.offer_accepted_at ?? null,
    offerAcceptanceAttachmentUrl:
      row.offer_acceptance_attachment_url ?? null,
    offerAcceptanceAttachmentMime:
      row.offer_acceptance_attachment_mime ?? null,
    offerAcceptanceAttachmentName:
      row.offer_acceptance_attachment_name ?? null,
    status: row.status,
    statusReason: row.status_reason ?? null,
    statusChangedByUserId:
      row.status_changed_by_user_id == null
        ? null
        : Number(row.status_changed_by_user_id),
    statusChangedAt: row.status_changed_at ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    jobTitle: row.job_title ?? null,
    jobCompanyName: row.job_company_name ?? null,
    jobActivityType: row.job_activity_type ?? null,
    jobDepartment: row.job_department ?? null,
    jobCategory: row.job_category ?? null,
    jobCreatedByUserId: jobCreatedByUserId > 0 ? jobCreatedByUserId : null,
    jobMerchantId:
      row.job_merchant_id == null ? null : Number(row.job_merchant_id),
    jobMerchantName: row.job_merchant_name ?? null,
    jobMerchantType: row.job_merchant_type ?? null,
    canChangeStatus,
    canAcceptOffer,
    applicant: {
      block: row.applicant_block ?? null,
      buildingNumber: row.applicant_building_number ?? null,
      apartment: row.applicant_apartment ?? null,
      imageUrl: row.applicant_image_url ?? null,
    },
  };
}

function mapRecommendation(row) {
  if (!row) return null;
  const linkedStatus = String(row.linked_application_status || "")
    .trim()
    .toLowerCase();
  const canAcceptToShortlist =
    Number(row.candidate_user_id || 0) > 0 &&
    (!row.linked_application_id ||
      (linkedStatus !== "shortlisted" && linkedStatus !== "hired"));
  return {
    id: Number(row.id),
    jobId: Number(row.job_id),
    sourceApplicationId:
      row.source_application_id == null
        ? null
        : Number(row.source_application_id),
    candidateUserId:
      row.candidate_user_id == null ? null : Number(row.candidate_user_id),
    candidateFullName: row.candidate_full_name || "",
    candidatePhone: row.candidate_phone || null,
    candidateEmail: row.candidate_email || null,
    candidateImageUrl: row.candidate_image_url || null,
    candidateWorkTitle: row.candidate_work_title || null,
    candidateWorkCompany: row.candidate_work_company || null,
    note: row.recommendation_note || null,
    attachmentUrl: row.attachment_url || null,
    attachmentMime: row.attachment_mime || null,
    attachmentName: row.attachment_name || null,
    linkedApplication:
      row.linked_application_id == null
        ? null
        : {
            id: Number(row.linked_application_id),
            status: row.linked_application_status || null,
            createdAt: row.linked_application_created_at || null,
            statusChangedAt: row.linked_application_status_changed_at || null,
          },
    canAcceptToShortlist,
    sourceApplication: row.source_application_id
      ? {
          id: Number(row.source_application_id),
          status: row.source_application_status || null,
          createdAt: row.source_application_created_at || null,
          message: row.source_application_message || null,
          resumeUrl: row.source_resume_url || null,
          attachmentUrl: row.source_attachment_url || null,
          attachmentMime: row.source_attachment_mime || null,
          attachmentName: row.source_attachment_name || null,
          expectedSalary:
            row.source_expected_salary == null
              ? null
              : Number(row.source_expected_salary),
          candidateFullName: row.source_candidate_full_name || null,
          candidatePhone: row.source_candidate_phone || null,
          candidateEmail: row.source_candidate_email || null,
          candidateImageUrl: row.source_candidate_image_url || null,
        }
      : null,
    createdAt: row.created_at || null,
    recommender: {
      userId: Number(row.recommended_by_user_id || 0),
      role: row.recommended_by_role || "admin",
      fullName: row.recommender_full_name || null,
      phone: row.recommender_phone || null,
      imageUrl: row.recommender_image_url || null,
    },
    sourceJob: row.source_job_id
      ? {
          id: Number(row.source_job_id),
          title: row.source_job_title || null,
          companyName: row.source_job_company_name || null,
        }
      : null,
  };
}

function isJobOpen(job) {
  if (!job || job.status !== "active") return false;
  if (!job.expires_at) return true;
  const expiresAt = new Date(job.expires_at).getTime();
  if (!Number.isFinite(expiresAt)) return false;
  return expiresAt >= Date.now();
}

async function canActorManageJob(job, actor) {
  if (!job) return false;
  if (actor?.isSuperAdmin === true) return true;

  const role = normalizeRole(actor?.role);
  const actorUserId = Number(actor?.userId || 0);

  if (role === "admin") return true;
  if (role === "owner" || role === "hr") {
    const merchant = await resolveManagerMerchant(actor);
    if (Number(job.merchant_id || 0) === Number(merchant.id)) return true;
    if (Number(job.created_by_user_id || 0) === actorUserId) return true;
  }

  return Number(job.created_by_user_id || 0) === actorUserId;
}

function withManagedMerchant(actor, merchantId) {
  if (!merchantId) return actor;
  return {
    ...actor,
    managedMerchantId: Number(merchantId),
  };
}

function toPagination(query = {}) {
  return {
    page: Math.max(1, Number(query.page) || 1),
    limit: Math.max(1, Math.min(100, Number(query.limit) || 20)),
  };
}

/**
 * يعيد قائمة الوظائف حسب الفلاتر والسياق الحالي للمستخدم.
 */
export async function listJobs(query, actor) {
  const userId = assertAuthedActor(actor);
  const paging = toPagination(query);
  const out = await repo.listJobs({
    viewerUserId: userId,
    query,
    page: paging.page,
    limit: paging.limit,
  });

  return {
    ...out,
    items: out.items.map((row) => mapJob(row, actor)),
  };
}

export async function listManagedJobs(query, actor) {
  await assertCanManageJobs(actor);
  const userId = assertAuthedActor(actor);
  const role = resolveActorRoleForJobs(actor);
  const paging = toPagination(query);
  const managerMerchant =
    role === "owner" || role === "hr" ? await resolveManagerMerchant(actor) : null;
  const scopedActor = withManagedMerchant(actor, managerMerchant?.id || null);

  const out = await repo.listManagedJobs({
    viewerUserId: userId,
    actorRole: role,
    actorUserId: userId,
    ownerMerchantId: managerMerchant?.id || null,
    publisherOnly: role === "admin",
    query,
    page: paging.page,
    limit: paging.limit,
  });

  return {
    ...out,
    items: out.items.map((row) => mapJob(row, scopedActor)),
  };
}

export async function listAdminReadableJobs(query, actor) {
  const { userId } = assertAdminOrSuper(actor);
  const paging = toPagination(query);
  const out = await repo.listManagedJobs({
    viewerUserId: userId,
    actorRole: "admin",
    actorUserId: userId,
    ownerMerchantId: null,
    publisherOnly: false,
    query,
    page: paging.page,
    limit: paging.limit,
  });
  return {
    ...out,
    items: out.items.map((row) => mapJob(row, actor)),
  };
}

/**
 * يعيد وظيفة واحدة مع قدرات الإدارة أو التقديم حسب actor الحالي.
 */
export async function getJobById(jobId, actor) {
  const userId = assertAuthedActor(actor);
  const row = await repo.findJobById(jobId, { viewerUserId: userId });
  if (!row) throw new AppError("JOB_NOT_FOUND", { status: 404 });

  const isVisible = isJobOpen(row);
  if (!isVisible) {
    const allowed = await canActorManageJob(row, actor);
    if (!allowed) throw new AppError("JOB_NOT_FOUND", { status: 404 });
  }

  return { job: mapJob(row, withManagedMerchant(actor, row.merchant_id)) };
}

/**
 * ينشئ وظيفة جديدة تحت مالك/HR/أدمن مخول.
 */
export async function createJob(dto, actor) {
  await assertCanManageJobs(actor);
  const userId = assertAuthedActor(actor);
  const role = resolveActorRoleForJobs(actor);

  let merchantId = dto.merchantId || null;
  let companyName = dto.companyName;
  let companyLogoUrl = dto.companyLogoUrl || null;

  if (role === "owner" || role === "hr") {
    const merchant = await resolveManagerMerchant(actor);
    merchantId = Number(merchant.id);
    companyName = companyName || merchant.name || "متجر";
    companyLogoUrl = companyLogoUrl || merchant.image_url || null;
  } else if (merchantId) {
    const merchant = await repo.findMerchantById(merchantId);
    if (!merchant?.id) {
      throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    }
    companyName = companyName || merchant.name || "متجر";
    companyLogoUrl = companyLogoUrl || merchant.image_url || null;
  }

  if (!companyName || !String(companyName).trim()) {
    companyName = role === "admin" ? "إدارة مسلكي" : "شركة";
  }

  const row = await repo.createJob({
    ...dto,
    merchantId,
    companyName: String(companyName).trim(),
    companyLogoUrl,
    createdByUserId: userId,
    createdByRole: role === "admin" ? "admin" : role === "hr" ? "hr" : "owner",
  });

  const hydrated = await repo.findJobById(row.id, { viewerUserId: userId });
  try {
    const recipients = await repo.listJobApplicationManagerRecipients({
      jobId: Number(row.id),
      excludeUserId: userId,
    });
    if (recipients.length > 0) {
      const actorProfile = await getUserPublicById(userId).catch(() => null);
      const actorName =
        actorProfile?.full_name ||
        actorProfile?.fullName ||
        actorProfile?.phone ||
        "Admin";
      const safeJobTitle = hydrated?.title || row.title || "New job";
      const safeCompany =
        hydrated?.company_name || row.company_name || "Company";
      await createManyNotifications(
        [...new Set(recipients)].map((targetUserId) => ({
          userId: Number(targetUserId),
          type: "jobs.posted",
          title: "New job has been posted",
          body: `${actorName} posted "${safeJobTitle}" for ${safeCompany}.`,
          payload: {
            target: "jobs_applications",
            jobId: Number(row.id),
            jobTitle: safeJobTitle,
            companyName: safeCompany,
            activityType: hydrated?.activity_type || row.activity_type || null,
            department: hydrated?.department || row.department || null,
          },
        }))
      );
    }
  } catch (notifyError) {
    console.error("[jobs] post notification failed", {
      jobId: Number(row.id),
      message: notifyError?.message || String(notifyError),
    });
  }
  return { job: mapJob(hydrated, actor) };
}

export async function updateJob(jobId, patch, actor) {
  await assertCanManageJobs(actor);
  const userId = assertAuthedActor(actor);
  const role = resolveActorRoleForJobs(actor);
  const current = await repo.findJobById(jobId, { viewerUserId: userId });
  if (!current) throw new AppError("JOB_NOT_FOUND", { status: 404 });

  const canManage = await canActorManageJob(current, actor);
  if (!canManage) throw new AppError("FORBIDDEN_JOB_MANAGEMENT", { status: 403 });

  const nextPatch = { ...patch };

  if (role === "owner" || role === "hr") {
    const merchant = await resolveManagerMerchant(actor);
    nextPatch.merchantId = Number(merchant.id);
    if (
      nextPatch.companyName == null ||
      String(nextPatch.companyName || "").trim().length === 0
    ) {
      nextPatch.companyName = current.company_name || merchant.name || "متجر";
    }
    if (nextPatch.companyLogoUrl === undefined) {
      nextPatch.companyLogoUrl = current.company_logo_url || merchant.image_url || null;
    }
  } else if (nextPatch.merchantId) {
    const merchant = await repo.findMerchantById(nextPatch.merchantId);
    if (!merchant?.id) {
      throw new AppError("MERCHANT_NOT_FOUND", { status: 404 });
    }
  }

  await repo.updateJob(jobId, nextPatch);
  const hydrated = await repo.findJobById(jobId, { viewerUserId: userId });
  return {
    job: mapJob(hydrated, withManagedMerchant(actor, current.merchant_id)),
  };
}

export async function updateJobStatus(jobId, status, actor) {
  await assertCanManageJobs(actor);
  const userId = assertAuthedActor(actor);
  const current = await repo.findJobById(jobId, { viewerUserId: userId });
  if (!current) throw new AppError("JOB_NOT_FOUND", { status: 404 });

  const canManage = await canActorManageJob(current, actor);
  if (!canManage) throw new AppError("FORBIDDEN_JOB_MANAGEMENT", { status: 403 });

  await repo.updateJob(jobId, { status });
  const hydrated = await repo.findJobById(jobId, { viewerUserId: userId });
  return {
    job: mapJob(hydrated, withManagedMerchant(actor, current.merchant_id)),
  };
}

export async function deleteJob(jobId, actor) {
  await assertCanManageJobs(actor);
  const userId = assertAuthedActor(actor);
  const current = await repo.findJobById(jobId, { viewerUserId: userId });
  if (!current) throw new AppError("JOB_NOT_FOUND", { status: 404 });

  const canManage = await canActorManageJob(current, actor);
  if (!canManage) throw new AppError("FORBIDDEN_JOB_MANAGEMENT", { status: 403 });

  await repo.softDeleteJob(jobId);
  return { ok: true };
}

/**
 * يسجل طلب توظيف جديد ويرسل الإشعارات للطرف الإداري المعني.
 */
export async function applyToJob(jobId, dto, actor) {
  const userId = assertAuthedActor(actor);
  const role = normalizeRole(actor.role);
  if (!isUserActor({ role })) {
    throw new AppError("FORBIDDEN_CUSTOMERS_ONLY", { status: 403 });
  }

  const job = await repo.findJobById(jobId, { viewerUserId: userId });
  if (!job) throw new AppError("JOB_NOT_FOUND", { status: 404 });
  if (!isJobOpen(job)) throw new AppError("JOB_NOT_OPEN", { status: 400 });

  const profile = await getUserPublicById(userId);
  if (!profile?.id) throw new AppError("USER_NOT_FOUND", { status: 404 });

  try {
    const row = await repo.createJobApplication({
      jobId,
      applicantUserId: userId,
      fullName: profile.full_name || profile.fullName || "مستخدم",
      phone: dto.phone || profile.phone || "",
      email: dto.email || null,
      message: dto.message || null,
      resumeUrl: dto.resumeUrl || null,
      attachmentUrl: dto.attachmentUrl || null,
      attachmentMime: dto.attachmentMime || null,
      attachmentName: dto.attachmentName || null,
      expectedSalary: dto.expectedSalary ?? null,
    });
    const mapped = mapApplication(row, actor);
    try {
      const managerRecipients = await repo.listJobApplicationManagerRecipients({
        jobId,
        excludeUserId: userId,
      });

      if (managerRecipients.length > 0) {
        const dedupedRecipients = [...new Set(managerRecipients)];
        await createManyNotifications(
          dedupedRecipients.map((managerUserId) => ({
            userId: managerUserId,
            type: "jobs.application.submitted",
            title: "متقدم جديد للوظيفة",
            body: `هناك متقدم جديد على وظيفة: ${job.title}`,
            payload: {
              target: "jobs_applications",
              jobId: Number(jobId),
              jobTitle: job.title,
              applicationId: Number(row.id),
              applicantUserId: Number(userId),
            },
          }))
        );
      }
    } catch (notifyError) {
      console.error("[jobs] manager notification failed", {
        jobId: Number(jobId),
        applicationId: Number(row.id),
        applicantUserId: Number(userId),
        message: notifyError?.message || String(notifyError),
      });
    }
    return { application: mapped };
  } catch (error) {
    if (String(error?.code || "") === "23505") {
      throw new AppError("JOB_ALREADY_APPLIED", { status: 409 });
    }
    throw error;
  }
}

export async function listMyApplications(query, actor) {
  const userId = assertAuthedActor(actor);
  const paging = toPagination(query);
  const out = await repo.listMyApplications({
    userId,
    page: paging.page,
    limit: paging.limit,
    status: query.status || null,
  });
  return {
    ...out,
    items: out.items.map((row) => mapApplication(row, actor)),
  };
}

export async function listJobApplications(jobId, query, actor) {
  await assertCanManageJobs(actor);
  const userId = assertAuthedActor(actor);

  const current = await repo.findJobById(jobId, { viewerUserId: userId });
  if (!current) throw new AppError("JOB_NOT_FOUND", { status: 404 });
  const canManage = await canActorManageJob(current, actor);
  if (!canManage) throw new AppError("FORBIDDEN_JOB_MANAGEMENT", { status: 403 });
  const scopedActor = withManagedMerchant(actor, current.merchant_id);

  const paging = toPagination(query);
  const out = await repo.listJobApplications({
    jobId,
    page: paging.page,
    limit: paging.limit,
    status: query.status || null,
  });
  const recommendations = await repo.listJobRecommendations({
    jobId,
    limit: 200,
  });

  return {
    ...out,
    items: out.items.map((row) => mapApplication(row, scopedActor)),
    recommendations: recommendations.map((row) => mapRecommendation(row)),
  };
}

export async function updateJobApplicationStatus(
  jobId,
  applicationId,
  status,
  reason,
  offer = {},
  actor
) {
  await assertCanManageJobs(actor);
  const userId = assertAuthedActor(actor);
  const current = await repo.findJobById(jobId, { viewerUserId: userId });
  if (!current) throw new AppError("JOB_NOT_FOUND", { status: 404 });
  const canManage = await canActorManageJob(current, actor);
  if (!canManage) throw new AppError("FORBIDDEN_JOB_MANAGEMENT", { status: 403 });
  const scopedActor = withManagedMerchant(actor, current.merchant_id);

  const row = await repo.updateJobApplicationStatus({
    jobId,
    applicationId,
    status,
    reason,
    actorUserId: userId,
    offerSalary: offer.offerSalary ?? null,
    offerWorkHours: offer.offerWorkHours ?? null,
    offerWorkDays: offer.offerWorkDays ?? null,
    offerMessage: offer.offerMessage ?? null,
    offerAttachmentUrl: offer.offerAttachmentUrl ?? null,
    offerAttachmentMime: offer.offerAttachmentMime ?? null,
    offerAttachmentName: offer.offerAttachmentName ?? null,
    offerSentByUserId:
      String(status || "").toLowerCase() === "hired" ? userId : null,
  });
  if (!row) throw new AppError("JOB_APPLICATION_NOT_FOUND", { status: 404 });
  if (String(status || "").toLowerCase() === "hired") {
    await repo.closeJobAfterHire(jobId).catch(() => null);
  }
  const mapped = mapApplication(row, scopedActor);

  const applicantUserId = Number(row.applicant_user_id || 0);
  if (applicantUserId > 0) {
    const statusLabel = {
      submitted: "received",
      shortlisted: "shortlisted",
      rejected: "rejected",
      hired: "hired",
      withdrawn: "withdrawn",
      dismissed_after_hire: "dismissed after hire",
      archived: "archived",
    }[status] || status;

    await createManyNotifications([
      {
        userId: applicantUserId,
        type: "jobs.application.status_updated",
        title: "Job application updated",
        body: `Your application for "${row.job_title || "the job"}" is now ${statusLabel}.`,
        payload: {
          target: "jobs_my_applications",
          jobId: Number(jobId),
          applicationId: Number(applicationId),
          status,
        },
      },
    ]);
  }

  return { application: mapped };
}

export async function acceptMyJobOffer(applicationId, dto, actor) {
  const userId = assertAuthedActor(actor);
  const role = normalizeRole(actor?.role);
  if (!isUserActor({ role })) {
    throw new AppError("FORBIDDEN_CUSTOMERS_ONLY", { status: 403 });
  }

  const current = await repo.findApplicationByIdForApplicant({
    applicationId,
    applicantUserId: userId,
  });
  if (!current) throw new AppError("JOB_APPLICATION_NOT_FOUND", { status: 404 });

  const hasOffer =
    String(current.status || "").toLowerCase() === "hired" &&
    current.offer_sent_at != null;
  if (!hasOffer) {
    throw new AppError("JOB_OFFER_NOT_AVAILABLE", { status: 400 });
  }

  let updated = current;
  if (!current.offer_accepted_at) {
    const accepted = await repo.acceptJobOffer({
      applicationId,
      applicantUserId: userId,
      acceptanceAttachmentUrl: dto.acceptanceAttachmentUrl || null,
      acceptanceAttachmentMime: dto.acceptanceAttachmentMime || null,
      acceptanceAttachmentName: dto.acceptanceAttachmentName || null,
    });
    if (!accepted) {
      throw new AppError("JOB_OFFER_ACCEPT_FAILED", { status: 400 });
    }
    updated = accepted;
  }

  const nextWorkTitle = String(updated.job_title || "").trim() || null;
  const nextWorkCompany = String(updated.job_company_name || "").trim() || null;
  const profile = await repo.updateApplicantWorkProfile({
    applicantUserId: userId,
    workTitle: nextWorkTitle,
    workCompany: nextWorkCompany,
  });

  try {
    const recipients = await repo.listJobApplicationManagerRecipients({
      jobId: Number(updated.job_id),
      excludeUserId: userId,
    });
    if (recipients.length > 0) {
      const actorProfile = await getUserPublicById(userId).catch(() => null);
      const actorName =
        actorProfile?.full_name ||
        actorProfile?.fullName ||
        actorProfile?.phone ||
        "Applicant";
      await createManyNotifications(
        [...new Set(recipients)].map((targetUserId) => ({
          userId: Number(targetUserId),
          type: "jobs.application.offer_accepted",
          title: "Job offer accepted",
          body: `${actorName} accepted the offer for "${updated.job_title || "the job"}".`,
          payload: {
            target: "jobs_applications",
            jobId: Number(updated.job_id),
            applicationId: Number(updated.id),
          },
        }))
      );
    }
  } catch (notifyError) {
    console.error("[jobs] offer-accept notification failed", {
      applicationId: Number(applicationId),
      message: notifyError?.message || String(notifyError),
    });
  }

  return {
    application: mapApplication(updated, actor),
    workProfile: {
      workTitle: profile?.work_title ?? nextWorkTitle,
      workCompany: profile?.work_company ?? nextWorkCompany,
    },
  };
}

export async function withdrawMyApplication(applicationId, reason, actor) {
  const userId = assertAuthedActor(actor);
  const role = normalizeRole(actor?.role);
  if (!isUserActor({ role })) {
    throw new AppError("FORBIDDEN_CUSTOMERS_ONLY", { status: 403 });
  }

  const current = await repo.findApplicationByIdForApplicant({
    applicationId,
    applicantUserId: userId,
  });
  if (!current) throw new AppError("JOB_APPLICATION_NOT_FOUND", { status: 404 });

  const currentStatus = String(current.status || "").trim().toLowerCase();
  if (!["submitted", "shortlisted", "hired"].includes(currentStatus)) {
    throw new AppError("JOB_APPLICATION_WITHDRAW_NOT_ALLOWED", { status: 400 });
  }
  if (current.offer_accepted_at) {
    throw new AppError("JOB_APPLICATION_WITHDRAW_AFTER_ACCEPT_NOT_ALLOWED", {
      status: 400,
    });
  }

  const updated = await repo.updateJobApplicationStatus({
    jobId: Number(current.job_id),
    applicationId: Number(applicationId),
    status: "withdrawn",
    reason,
    actorUserId: userId,
  });
  if (!updated) {
    throw new AppError("JOB_APPLICATION_NOT_FOUND", { status: 404 });
  }

  try {
    const recipients = await repo.listJobApplicationManagerRecipients({
      jobId: Number(updated.job_id),
      excludeUserId: userId,
    });
    if (recipients.length > 0) {
      const actorProfile = await getUserPublicById(userId).catch(() => null);
      const actorName =
        actorProfile?.full_name ||
        actorProfile?.fullName ||
        actorProfile?.phone ||
        "Applicant";
      await createManyNotifications(
        [...new Set(recipients)].map((targetUserId) => ({
          userId: Number(targetUserId),
          type: "jobs.application.withdrawn",
          title: "Application withdrawn",
          body: `${actorName} withdrew the application for "${updated.job_title || "the job"}".`,
          payload: {
            target: "jobs_applications",
            jobId: Number(updated.job_id),
            applicationId: Number(updated.id),
            status: "withdrawn",
          },
        }))
      );
    }
  } catch (notifyError) {
    console.error("[jobs] withdraw notification failed", {
      applicationId: Number(applicationId),
      message: notifyError?.message || String(notifyError),
    });
  }

  return {
    application: mapApplication(updated, actor),
  };
}

export async function listManagerApplications(query, actor) {
  await assertCanManageJobs(actor);
  const userId = assertAuthedActor(actor);
  const role = resolveActorRoleForJobs(actor);
  const paging = toPagination(query);
  const managerMerchant =
    role === "owner" || role === "hr" ? await resolveManagerMerchant(actor) : null;
  const scopedActor = withManagedMerchant(actor, managerMerchant?.id || null);

  const out = await repo.listManagerApplications({
    actorUserId: userId,
    actorRole: role,
    ownerMerchantId: managerMerchant?.id || null,
    publisherOnly: role === "admin",
    query,
    page: paging.page,
    limit: paging.limit,
  });

  return {
    ...out,
    items: out.items.map((row) => mapApplication(row, scopedActor)),
  };
}

export async function listTalentPool(query, actor) {
  await assertCanManageJobs(actor);
  const userId = assertAuthedActor(actor);
  const role = resolveActorRoleForJobs(actor);
  const managerMerchant =
    role === "owner" || role === "hr" ? await resolveManagerMerchant(actor) : null;

  const groups = await repo.listTalentPoolGroups({
    actorUserId: userId,
    actorRole: role,
    ownerMerchantId: managerMerchant?.id || null,
    publisherOnly: role === "admin",
    query,
  });

  return {
    groups: groups.map((row) => ({
      activityType: row.activity_type,
      department: row.department,
      totalApplications: Number(row.total_applications || 0),
      uniqueApplicants: Number(row.unique_applicants || 0),
      submittedCount: Number(row.submitted_count || 0),
      shortlistedCount: Number(row.shortlisted_count || 0),
      rejectedCount: Number(row.rejected_count || 0),
      hiredCount: Number(row.hired_count || 0),
      withdrawnCount: Number(row.withdrawn_count || 0),
      dismissedAfterHireCount: Number(row.dismissed_after_hire_count || 0),
      archivedCount: Number(row.archived_count || 0),
      lastApplicationAt: row.last_application_at || null,
    })),
  };
}

export async function listSuperAdminApplicationsMonitor(query, actor) {
  if (actor?.isSuperAdmin !== true) {
    throw new AppError("FORBIDDEN_SUPER_ADMIN_ONLY", { status: 403 });
  }

  const userId = assertAuthedActor(actor);
  const paging = toPagination(query);

  const [groups, applications] = await Promise.all([
    repo.listTalentPoolGroups({
      actorUserId: userId,
      actorRole: "admin",
      ownerMerchantId: null,
      publisherOnly: false,
      query,
    }),
    repo.listManagerApplications({
      actorUserId: userId,
      actorRole: "admin",
      ownerMerchantId: null,
      publisherOnly: false,
      query,
      page: paging.page,
      limit: paging.limit,
    }),
  ]);

  return {
    groups: groups.map((row) => ({
      activityType: row.activity_type,
      department: row.department,
      totalApplications: Number(row.total_applications || 0),
      uniqueApplicants: Number(row.unique_applicants || 0),
      submittedCount: Number(row.submitted_count || 0),
      shortlistedCount: Number(row.shortlisted_count || 0),
      rejectedCount: Number(row.rejected_count || 0),
      hiredCount: Number(row.hired_count || 0),
      withdrawnCount: Number(row.withdrawn_count || 0),
      dismissedAfterHireCount: Number(row.dismissed_after_hire_count || 0),
      archivedCount: Number(row.archived_count || 0),
      lastApplicationAt: row.last_application_at || null,
    })),
    applications: {
      ...applications,
      items: applications.items.map((row) => mapApplication(row, actor)),
    },
  };
}

export async function listRecommendationCandidatesForJob(jobId, query, actor) {
  assertAdminOrSuper(actor);
  const viewerUserId = assertAuthedActor(actor);
  const job = await repo.findJobById(jobId, { viewerUserId });
  if (!job) throw new AppError("JOB_NOT_FOUND", { status: 404 });

  const rows = await repo.listRecommendationCandidatesForJob({
    jobId,
    search: query.search || null,
    limit: query.limit || 40,
  });

  return {
    job: {
      id: Number(job.id),
      title: job.title || "",
      companyName: job.company_name || "",
      activityType: job.activity_type || "general_business",
      department: job.department || "operations",
      category: job.category || "",
    },
    items: rows.map((row) => ({
      sourceApplicationId: Number(row.source_application_id),
      sourceJobId: Number(row.source_job_id),
      sourceJobTitle: row.source_job_title || null,
      sourceCompanyName: row.source_company_name || null,
      sourceStatus: row.source_status || "submitted",
      sourceCreatedAt: row.source_created_at || null,
      candidateUserId: Number(row.applicant_user_id || 0),
      candidateFullName: row.candidate_full_name || "",
      candidatePhone: row.candidate_phone || null,
      candidateEmail: row.candidate_email || null,
      candidateImageUrl: row.candidate_image_url || null,
      candidateWorkTitle: row.candidate_work_title || null,
      candidateWorkCompany: row.candidate_work_company || null,
      applicationsCount: Number(row.applications_count || 0),
      activityType: row.source_activity_type || null,
      department: row.source_department || null,
      category: row.source_category || null,
    })),
  };
}

export async function createJobRecommendation(jobId, dto, actor) {
  const { userId, role } = assertAdminOrSuper(actor);
  const viewerUserId = assertAuthedActor(actor);
  const job = await repo.findJobById(jobId, { viewerUserId });
  if (!job) throw new AppError("JOB_NOT_FOUND", { status: 404 });

  let candidateUserId = dto.candidateUserId || null;
  let candidateFullName = dto.candidateFullName || null;
  let candidatePhone = dto.candidatePhone || null;
  let candidateEmail = dto.candidateEmail || null;
  let candidateWorkTitle = dto.candidateWorkTitle || null;
  let candidateWorkCompany = dto.candidateWorkCompany || null;
  let sourceApplicationId = dto.sourceApplicationId || null;

  if (sourceApplicationId) {
    const source = await repo.findJobApplicationById(sourceApplicationId);
    if (!source) {
      throw new AppError("SOURCE_APPLICATION_NOT_FOUND", { status: 404 });
    }
    candidateUserId = Number(source.applicant_user_id || 0) || null;
    candidateFullName =
      source.applicant_profile_full_name || source.full_name || candidateFullName;
    candidatePhone =
      source.applicant_profile_phone || source.phone || candidatePhone;
    candidateEmail = source.applicant_email || candidateEmail;
    candidateWorkTitle = source.applicant_work_title || candidateWorkTitle;
    candidateWorkCompany = source.applicant_work_company || candidateWorkCompany;
  } else if (candidateUserId) {
    const user = await repo.findUserProfileById(candidateUserId);
    if (!user) {
      throw new AppError("CANDIDATE_USER_NOT_FOUND", { status: 404 });
    }
    candidateFullName = candidateFullName || user.full_name || null;
    candidatePhone = candidatePhone || user.phone || null;
    candidateWorkTitle = candidateWorkTitle || user.work_title || null;
    candidateWorkCompany = candidateWorkCompany || user.work_company || null;
  }

  if (!candidateFullName || !String(candidateFullName).trim()) {
    throw new AppError("CANDIDATE_FULL_NAME_REQUIRED", { status: 400 });
  }

  let inserted;
  try {
    inserted = await repo.createJobRecommendation({
      jobId,
      recommendedByUserId: userId,
      recommendedByRole: actor?.isSuperAdmin === true ? "admin" : role,
      sourceApplicationId,
      candidateUserId,
      candidateFullName: String(candidateFullName).trim().slice(0, 180),
      candidatePhone,
      candidateEmail,
      candidateWorkTitle,
      candidateWorkCompany,
      recommendationNote: dto.note || null,
      attachmentUrl: dto.attachmentUrl || null,
      attachmentMime: dto.attachmentMime || null,
      attachmentName: dto.attachmentName || null,
    });
  } catch (error) {
    if (String(error?.code || "") === "23505") {
      throw new AppError("JOB_RECOMMENDATION_ALREADY_EXISTS", { status: 409 });
    }
    throw error;
  }

  try {
    const recipients = await repo.listJobApplicationManagerRecipients({
      jobId,
      excludeUserId: userId,
    });
    if (recipients.length > 0) {
      const actorProfile = await getUserPublicById(userId).catch(() => null);
      const actorName =
        actorProfile?.full_name ||
        actorProfile?.fullName ||
        actorProfile?.phone ||
        "Admin";
      const safeDepartment = String(job.department || "")
        .trim()
        .replace(/_/g, " ");
      await createManyNotifications(
        [...new Set(recipients)].map((targetUserId) => ({
          userId: Number(targetUserId),
          type: "jobs.recommendation.submitted",
          title: "Employee recommendation received",
          body: `${actorName} recommended a candidate for "${job.title}"${safeDepartment ? ` (${safeDepartment})` : ""}.`,
          payload: {
            target: "jobs_applications",
            jobId: Number(jobId),
            recommendationId: Number(inserted.id),
            candidateFullName: String(candidateFullName || "").trim(),
            sourceApplicationId:
              sourceApplicationId == null ? null : Number(sourceApplicationId),
          },
        }))
      );
    }
  } catch (notifyError) {
    console.error("[jobs] recommendation notification failed", {
      jobId: Number(jobId),
      recommendationId: Number(inserted.id),
      message: notifyError?.message || String(notifyError),
    });
  }

  const rows = await repo.listJobRecommendations({
    jobId,
    limit: 1,
  });
  const hydrated = rows[0] || inserted;
  return { recommendation: mapRecommendation(hydrated) };
}

export async function listJobRecommendations(jobId, actor) {
  await assertCanManageJobs(actor);
  const userId = assertAuthedActor(actor);
  const current = await repo.findJobById(jobId, { viewerUserId: userId });
  if (!current) throw new AppError("JOB_NOT_FOUND", { status: 404 });
  const canManage = await canActorManageJob(current, actor);
  if (!canManage) throw new AppError("FORBIDDEN_JOB_MANAGEMENT", { status: 403 });

  const rows = await repo.listJobRecommendations({
    jobId,
    limit: 300,
  });
  return {
    items: rows.map((row) => mapRecommendation(row)),
  };
}

export async function acceptJobRecommendation(
  jobId,
  recommendationId,
  dto,
  actor
) {
  await assertCanManageJobs(actor);
  const userId = assertAuthedActor(actor);
  const job = await repo.findJobById(jobId, { viewerUserId: userId });
  if (!job) throw new AppError("JOB_NOT_FOUND", { status: 404 });
  const canManage = await canActorManageJob(job, actor);
  if (!canManage) throw new AppError("FORBIDDEN_JOB_MANAGEMENT", { status: 403 });
  const scopedActor = withManagedMerchant(actor, job.merchant_id);

  const recommendation = await repo.findJobRecommendationById({
    jobId,
    recommendationId,
  });
  if (!recommendation) {
    throw new AppError("JOB_RECOMMENDATION_NOT_FOUND", { status: 404 });
  }

  const candidateUserId = Number(recommendation.candidate_user_id || 0);
  if (!Number.isFinite(candidateUserId) || candidateUserId <= 0) {
    throw new AppError("JOB_RECOMMENDATION_REQUIRES_REGISTERED_CANDIDATE", {
      status: 400,
    });
  }

  const profile = await repo.findUserProfileById(candidateUserId);
  if (!profile?.id) {
    throw new AppError("CANDIDATE_USER_NOT_FOUND", { status: 404 });
  }

  const reason =
    String(dto?.reason || "").trim() ||
    `Accepted recommendation #${Number(recommendationId)}`;
  const normalizedStatus = String(
    recommendation.linked_application_status || ""
  )
    .trim()
    .toLowerCase();

  let row = null;
  if (
    recommendation.linked_application_id &&
    ["shortlisted", "hired"].includes(normalizedStatus)
  ) {
    row = await repo.findJobApplicationById(recommendation.linked_application_id);
  } else {
    let applicationId = recommendation.linked_application_id
      ? Number(recommendation.linked_application_id)
      : null;

    if (!applicationId) {
      const created = await repo.createJobApplication({
        jobId: Number(jobId),
        applicantUserId: candidateUserId,
        fullName:
          recommendation.candidate_full_name ||
          profile.full_name ||
          "Candidate",
        phone:
          recommendation.candidate_phone || profile.phone || "00000000000",
        email: recommendation.candidate_email || null,
        message: recommendation.recommendation_note || null,
        resumeUrl: recommendation.source_resume_url || null,
        attachmentUrl: recommendation.source_attachment_url || null,
        attachmentMime: recommendation.source_attachment_mime || null,
        attachmentName: recommendation.source_attachment_name || null,
        expectedSalary:
          recommendation.source_expected_salary == null
            ? null
            : Number(recommendation.source_expected_salary),
      }).catch((error) => {
        if (String(error?.code || "") !== "23505") throw error;
        return null;
      });

      if (created?.id) {
        applicationId = Number(created.id);
      } else {
        const existing = await repo.findJobApplicationByJobAndApplicant({
          jobId: Number(jobId),
          applicantUserId: candidateUserId,
        });
        applicationId = existing?.id ? Number(existing.id) : null;
      }
    }

    if (!applicationId) {
      throw new AppError("RECOMMENDATION_SHORTLIST_FAILED", { status: 400 });
    }

    row = await repo.updateJobApplicationStatus({
      jobId: Number(jobId),
      applicationId: Number(applicationId),
      status: "shortlisted",
      reason,
      actorUserId: userId,
    });
  }

  if (!row) {
    throw new AppError("JOB_APPLICATION_NOT_FOUND", { status: 404 });
  }

  try {
    await createManyNotifications([
      {
        userId: candidateUserId,
        type: "jobs.application.status_updated",
        title: "تم قبول ترشيحك",
        body: `تم قبول ترشيحك لوظيفة "${row.job_title || "الوظيفة"}" وأصبحت ضمن المرشحين.`,
        payload: {
          target: "jobs_my_applications",
          jobId: Number(jobId),
          applicationId: Number(row.id),
          status: "shortlisted",
          recommendationId: Number(recommendationId),
        },
      },
    ]);
  } catch (notifyError) {
    console.error("[jobs] recommendation accept notify failed", {
      recommendationId: Number(recommendationId),
      message: notifyError?.message || String(notifyError),
    });
  }

  const hydratedRecommendation = await repo.findJobRecommendationById({
    jobId,
    recommendationId,
  });

  return {
    application: mapApplication(row, scopedActor),
    recommendation: mapRecommendation(hydratedRecommendation || recommendation),
  };
}

export async function getJobsFilterMeta() {
  const meta = await repo.getJobFilterMeta();
  const taxonomy = getJobsTaxonomyMeta();
  return {
    ...meta,
    employmentTypes: [
      "full_time",
      "part_time",
      "contract",
      "internship",
      "freelance",
    ],
    workplaceTypes: ["on_site", "hybrid", "remote"],
    experienceLevels: ["entry", "junior", "mid", "senior", "lead", "manager"],
    salaryPeriods: ["hourly", "monthly", "yearly", "project"],
    sortOptions: ["recent", "salary_high", "salary_low", "expires_soon"],
    activityTypes: taxonomy.activityTypes,
    departmentsByActivity: taxonomy.departmentsByActivity,
  };
}
