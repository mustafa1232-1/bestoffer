import { Router } from "express";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { jobApplicationAttachmentUpload } from "../../shared/utils/upload.js";
import * as c from "./jobs.controller.js";

export const jobsRouter = Router();

jobsRouter.use(requireAuth);

jobsRouter.get("/filters/meta", c.getFilterMeta);
jobsRouter.get("/mine/applications", c.listMyApplications);
jobsRouter.get("/manage/mine", c.listManagedJobs);
jobsRouter.get("/manage/read-only", c.listAdminReadableJobs);
jobsRouter.get("/applications/manage", c.listManagerApplications);
jobsRouter.get("/applications/monitor", c.listSuperAdminApplicationsMonitor);
jobsRouter.get("/applications/talent-pool", c.listTalentPool);
jobsRouter.post(
  "/applications/:applicationId/accept-offer",
  jobApplicationAttachmentUpload.single("attachmentFile"),
  c.acceptMyJobOffer
);
jobsRouter.post("/applications/:applicationId/withdraw", c.withdrawMyApplication);

jobsRouter.get("/", c.listJobs);
jobsRouter.get("/:jobId/recommendations", c.listJobRecommendations);
jobsRouter.get(
  "/:jobId/recommendations/candidates",
  c.listRecommendationCandidatesForJob
);
jobsRouter.post(
  "/:jobId/recommendations",
  jobApplicationAttachmentUpload.single("attachmentFile"),
  c.createJobRecommendation
);
jobsRouter.post(
  "/:jobId/recommendations/:recommendationId/accept",
  c.acceptJobRecommendation
);
jobsRouter.get("/:jobId/applications", c.listJobApplications);
jobsRouter.patch(
  "/:jobId/applications/:applicationId/status",
  jobApplicationAttachmentUpload.single("attachmentFile"),
  c.updateJobApplicationStatus
);
jobsRouter.get("/:jobId", c.getJobById);
jobsRouter.post(
  "/:jobId/apply",
  jobApplicationAttachmentUpload.single("attachmentFile"),
  c.applyToJob
);

jobsRouter.post("/", c.createJob);
jobsRouter.patch("/:jobId", c.updateJob);
jobsRouter.patch("/:jobId/status", c.updateJobStatus);
jobsRouter.delete("/:jobId", c.deleteJob);
