import * as service from "./jobs.service.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";
import {
  validateApplicationId,
  validateApplyToJobBody,
  validateCreateRecommendationBody,
  validateAcceptRecommendationBody,
  validateCreateJobBody,
  validateJobId,
  validateListJobApplicationsQuery,
  validateListJobsQuery,
  validateListManagerApplicationsQuery,
  validateListRecommendationCandidatesQuery,
  validateListTalentPoolQuery,
  validateUpdateApplicationStatusBody,
  validateWithdrawMyApplicationBody,
  validateUpdateJobBody,
  validateUpdateJobStatusBody,
} from "./jobs.validators.js";

/**
 * Purpose:
 * controllers الوظائف. تطبق validation وتبني actor context ثم تستدعي
 * `jobs.service.js`.
 */

/**
 * helper موحد لإرجاع validation errors بصيغة متسقة.
 */
function badRequest(res, fields) {
  return res.status(400).json({
    message: "VALIDATION_ERROR",
    fields,
  });
}

/**
 * يستخرج actor context الموحد من request لاستخدامه عبر كل مسارات الوظائف.
 */
function actorFromReq(req) {
  return {
    userId: req.userId,
    role: req.userRole,
    isSuperAdmin: req.userIsSuperAdmin === true,
  };
}

/**
 * يعيد الوظائف العامة حسب query الحالية.
 */
export async function listJobs(req, res, next) {
  try {
    const query = validateListJobsQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listJobs(query.value, actorFromReq(req));
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listManagedJobs(req, res, next) {
  try {
    const query = validateListJobsQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const normalized = {
      ...query.value,
      onlyOpen:
        req.query?.onlyOpen === undefined ? false : query.value.onlyOpen,
    };

    const out = await service.listManagedJobs(normalized, actorFromReq(req));
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listAdminReadableJobs(req, res, next) {
  try {
    const query = validateListJobsQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const normalized = {
      ...query.value,
      onlyOpen:
        req.query?.onlyOpen === undefined ? true : query.value.onlyOpen,
    };

    const out = await service.listAdminReadableJobs(
      normalized,
      actorFromReq(req)
    );
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getJobById(req, res, next) {
  try {
    const job = validateJobId(req.params.jobId);
    if (!job.ok) return badRequest(res, job.errors);

    const out = await service.getJobById(job.value, actorFromReq(req));
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

/**
 * ينشئ وظيفة جديدة للمستخدم المخول.
 */
export async function createJob(req, res, next) {
  try {
    const body = validateCreateJobBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const out = await service.createJob(body.value, actorFromReq(req));
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function updateJob(req, res, next) {
  try {
    const job = validateJobId(req.params.jobId);
    if (!job.ok) return badRequest(res, job.errors);

    const body = validateUpdateJobBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const out = await service.updateJob(job.value, body.value, actorFromReq(req));
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function updateJobStatus(req, res, next) {
  try {
    const job = validateJobId(req.params.jobId);
    if (!job.ok) return badRequest(res, job.errors);

    const body = validateUpdateJobStatusBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const out = await service.updateJobStatus(
      job.value,
      body.value.status,
      actorFromReq(req)
    );
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function deleteJob(req, res, next) {
  try {
    const job = validateJobId(req.params.jobId);
    if (!job.ok) return badRequest(res, job.errors);

    const out = await service.deleteJob(job.value, actorFromReq(req));
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

/**
 * يسجل طلب توظيف جديد مع ملف مرفق اختياري.
 */
export async function applyToJob(req, res, next) {
  try {
    const job = validateJobId(req.params.jobId);
    if (!job.ok) return badRequest(res, job.errors);

    const body = validateApplyToJobBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const attachmentUrl = buildUploadedFileUrl(req, req.file);
    const out = await service.applyToJob(
      job.value,
      {
        ...body.value,
        attachmentUrl,
        attachmentMime: req.file?.mimetype || null,
        attachmentName:
          req.file?.originalname || req.file?.filename || null,
      },
      actorFromReq(req)
    );
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listMyApplications(req, res, next) {
  try {
    const query = validateListJobApplicationsQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listMyApplications(query.value, actorFromReq(req));
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listManagerApplications(req, res, next) {
  try {
    const query = validateListManagerApplicationsQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listManagerApplications(
      query.value,
      actorFromReq(req)
    );
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listSuperAdminApplicationsMonitor(req, res, next) {
  try {
    const query = validateListManagerApplicationsQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listSuperAdminApplicationsMonitor(
      query.value,
      actorFromReq(req)
    );
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listTalentPool(req, res, next) {
  try {
    const query = validateListTalentPoolQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listTalentPool(query.value, actorFromReq(req));
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listRecommendationCandidatesForJob(req, res, next) {
  try {
    const job = validateJobId(req.params.jobId);
    if (!job.ok) return badRequest(res, job.errors);

    const query = validateListRecommendationCandidatesQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listRecommendationCandidatesForJob(
      job.value,
      query.value,
      actorFromReq(req)
    );
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function createJobRecommendation(req, res, next) {
  try {
    const job = validateJobId(req.params.jobId);
    if (!job.ok) return badRequest(res, job.errors);

    const body = validateCreateRecommendationBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const attachmentUrl = buildUploadedFileUrl(req, req.file);
    const out = await service.createJobRecommendation(
      job.value,
      {
        ...body.value,
        attachmentUrl,
        attachmentMime: req.file?.mimetype || null,
        attachmentName: req.file?.originalname || req.file?.filename || null,
      },
      actorFromReq(req)
    );
    return res.status(201).json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listJobRecommendations(req, res, next) {
  try {
    const job = validateJobId(req.params.jobId);
    if (!job.ok) return badRequest(res, job.errors);

    const out = await service.listJobRecommendations(
      job.value,
      actorFromReq(req)
    );
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function acceptJobRecommendation(req, res, next) {
  try {
    const job = validateJobId(req.params.jobId);
    if (!job.ok) return badRequest(res, job.errors);

    const recommendation = validateApplicationId(req.params.recommendationId);
    if (!recommendation.ok) return badRequest(res, recommendation.errors);

    const body = validateAcceptRecommendationBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const out = await service.acceptJobRecommendation(
      job.value,
      recommendation.value,
      body.value,
      actorFromReq(req)
    );
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function listJobApplications(req, res, next) {
  try {
    const job = validateJobId(req.params.jobId);
    if (!job.ok) return badRequest(res, job.errors);

    const query = validateListJobApplicationsQuery(req.query || {});
    if (!query.ok) return badRequest(res, query.errors);

    const out = await service.listJobApplications(
      job.value,
      query.value,
      actorFromReq(req)
    );
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function updateJobApplicationStatus(req, res, next) {
  try {
    const job = validateJobId(req.params.jobId);
    if (!job.ok) return badRequest(res, job.errors);

    const application = validateApplicationId(req.params.applicationId);
    if (!application.ok) return badRequest(res, application.errors);

    const body = validateUpdateApplicationStatusBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const out = await service.updateJobApplicationStatus(
      job.value,
      application.value,
      body.value.status,
      body.value.reason ?? null,
      {
        offerSalary: body.value.offerSalary ?? null,
        offerWorkHours: body.value.offerWorkHours ?? null,
        offerWorkDays: body.value.offerWorkDays ?? null,
        offerMessage: body.value.offerMessage ?? null,
        offerAttachmentUrl: buildUploadedFileUrl(req, req.file),
        offerAttachmentMime: req.file?.mimetype || null,
        offerAttachmentName: req.file?.originalname || req.file?.filename || null,
      },
      actorFromReq(req)
    );
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function acceptMyJobOffer(req, res, next) {
  try {
    const application = validateApplicationId(req.params.applicationId);
    if (!application.ok) return badRequest(res, application.errors);

    const out = await service.acceptMyJobOffer(
      application.value,
      {
        acceptanceAttachmentUrl: buildUploadedFileUrl(req, req.file),
        acceptanceAttachmentMime: req.file?.mimetype || null,
        acceptanceAttachmentName:
          req.file?.originalname || req.file?.filename || null,
      },
      actorFromReq(req)
    );
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function withdrawMyApplication(req, res, next) {
  try {
    const application = validateApplicationId(req.params.applicationId);
    if (!application.ok) return badRequest(res, application.errors);

    const body = validateWithdrawMyApplicationBody(req.body || {});
    if (!body.ok) return badRequest(res, body.errors);

    const out = await service.withdrawMyApplication(
      application.value,
      body.value.reason,
      actorFromReq(req)
    );
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}

export async function getFilterMeta(req, res, next) {
  try {
    const out = await service.getJobsFilterMeta();
    return res.json(out);
  } catch (error) {
    return next(error);
  }
}
