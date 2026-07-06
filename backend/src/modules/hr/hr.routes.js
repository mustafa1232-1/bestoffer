import { Router } from "express";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { imageUpload } from "../../shared/utils/upload.js";
import * as c from "./hr.controller.js";

export const hrRouter = Router();

hrRouter.use(requireAuth);

hrRouter.get("/dashboard", c.dashboard);
hrRouter.get("/employees", c.listEmployees);
hrRouter.post("/employees/invite", c.inviteEmployee);
hrRouter.post("/employees/upsert", c.upsertEmployee);
hrRouter.get("/employees/activity-log", c.listEmployeeActivityLogs);

hrRouter.get("/attendance", c.listAttendance);
hrRouter.post("/attendance/upsert", c.upsertAttendance);
hrRouter.post("/attendance/check-in", imageUpload.single("imageFile"), c.selfCheckIn);
hrRouter.post("/attendance/check-out", imageUpload.single("imageFile"), c.selfCheckOut);

hrRouter.post("/payroll/batches/build", c.buildPayroll);
hrRouter.get("/payroll/batches", c.listPayrollBatches);
hrRouter.get("/payroll/batches/:batchId", c.getPayrollBatch);
hrRouter.post("/payroll/batches/:batchId/submit", c.submitPayrollBatch);
hrRouter.post("/payroll/batches/:batchId/close", c.closePayrollBatch);

hrRouter.get("/leave-requests", c.listLeaveRequests);
hrRouter.post("/leave-requests", c.createLeaveRequest);
hrRouter.post("/leave-requests/:leaveId/decide", c.decideLeaveRequest);

hrRouter.get("/salary-actions", c.listSalaryActions);
hrRouter.post("/salary-actions", c.createSalaryAction);
hrRouter.post("/salary-actions/:actionId/status", c.updateSalaryActionStatus);

hrRouter.get("/archive/attendance", c.attendanceArchive);

hrRouter.get("/my/profiles", c.myProfiles);
hrRouter.get("/my/attendance", c.listMyAttendance);
hrRouter.get("/my/leave-requests", c.listMyLeaveRequests);
hrRouter.post("/my/leave-requests", c.createMyLeaveRequest);
hrRouter.get("/my/advance-requests", c.listMyAdvanceRequests);
hrRouter.post("/my/advance-requests", c.createMyAdvanceRequest);

hrRouter.get("/advance-requests", c.listAdvanceRequests);
hrRouter.post("/advance-requests/:requestId/decide", c.decideAdvanceRequest);
