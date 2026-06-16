import * as service from "./hr.service.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";
import {
  validateCreateAdvanceRequest,
  validateCreateLeaveRequest,
  validateCreateMyLeaveRequest,
  validateCreateSalaryAction,
  validateDecideAdvanceRequest,
  validateDecideLeaveRequest,
  validatePayrollBuild,
  validateSelfAttendance,
  validateUpdateSalaryActionStatus,
  validateUpsertAttendance,
  validateUpsertEmployee,
} from "./hr.validators.js";

function toIntOrNull(value) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;
  return parsed;
}

function actorFromReq(req) {
  return {
    userId: req.userId,
    role: req.userRole,
    isSuperAdmin: req.userIsSuperAdmin === true,
  };
}

export async function dashboard(req, res, next) {
  try {
    const out = await service.getDashboard(actorFromReq(req), {
      merchantId: toIntOrNull(req.query?.merchantId),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listEmployees(req, res, next) {
  try {
    const out = await service.listEmployees(actorFromReq(req), {
      merchantId: toIntOrNull(req.query?.merchantId),
      search: req.query?.search || "",
      limit: Number(req.query?.limit || 120),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function upsertEmployee(req, res, next) {
  try {
    const v = validateUpsertEmployee(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.upsertEmployee(actorFromReq(req), v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listAttendance(req, res, next) {
  try {
    const out = await service.listAttendance(actorFromReq(req), {
      merchantId: toIntOrNull(req.query?.merchantId),
      employeeUserId: toIntOrNull(req.query?.employeeUserId),
      dateFrom: req.query?.dateFrom || null,
      dateTo: req.query?.dateTo || null,
      limit: Number(req.query?.limit || 200),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function upsertAttendance(req, res, next) {
  try {
    const v = validateUpsertAttendance(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.upsertAttendance(actorFromReq(req), v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function selfCheckIn(req, res, next) {
  try {
    const v = validateSelfAttendance(req.body || {});
    const imageUrl = req.file ? buildUploadedFileUrl(req, req.file) : null;
    const out = await service.selfCheckIn(actorFromReq(req), {
      ...v.value,
      imageUrl,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function selfCheckOut(req, res, next) {
  try {
    const v = validateSelfAttendance(req.body || {});
    const imageUrl = req.file ? buildUploadedFileUrl(req, req.file) : null;
    const out = await service.selfCheckOut(actorFromReq(req), {
      ...v.value,
      imageUrl,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function buildPayroll(req, res, next) {
  try {
    const v = validatePayrollBuild(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.buildPayrollBatch(actorFromReq(req), v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listPayrollBatches(req, res, next) {
  try {
    const out = await service.listPayrollBatches(actorFromReq(req), {
      merchantId: toIntOrNull(req.query?.merchantId),
      limit: Number(req.query?.limit || 40),
      status: req.query?.status || null,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function getPayrollBatch(req, res, next) {
  try {
    const out = await service.getPayrollBatch(
      actorFromReq(req),
      Number(req.params.batchId),
      {
        merchantId: toIntOrNull(req.query?.merchantId),
      }
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function submitPayrollBatch(req, res, next) {
  try {
    const out = await service.submitPayrollBatch(
      actorFromReq(req),
      Number(req.params.batchId),
      {
        merchantId: toIntOrNull(req.body?.merchantId ?? req.query?.merchantId),
      }
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function closePayrollBatch(req, res, next) {
  try {
    const out = await service.closePayrollBatch(
      actorFromReq(req),
      Number(req.params.batchId),
      {
        merchantId: toIntOrNull(req.body?.merchantId ?? req.query?.merchantId),
      }
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listLeaveRequests(req, res, next) {
  try {
    const out = await service.listLeaveRequests(actorFromReq(req), {
      merchantId: toIntOrNull(req.query?.merchantId),
      employeeUserId: toIntOrNull(req.query?.employeeUserId),
      dateFrom: req.query?.dateFrom || null,
      dateTo: req.query?.dateTo || null,
      status: req.query?.status || null,
      limit: Number(req.query?.limit || 120),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function createLeaveRequest(req, res, next) {
  try {
    const v = validateCreateLeaveRequest(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.createLeaveRequest(actorFromReq(req), v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function decideLeaveRequest(req, res, next) {
  try {
    const v = validateDecideLeaveRequest(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.decideLeaveRequest(
      actorFromReq(req),
      Number(req.params.leaveId),
      v.value
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listSalaryActions(req, res, next) {
  try {
    const out = await service.listSalaryActions(actorFromReq(req), {
      merchantId: toIntOrNull(req.query?.merchantId),
      employeeUserId: toIntOrNull(req.query?.employeeUserId),
      periodYear: toIntOrNull(req.query?.periodYear),
      periodMonth: toIntOrNull(req.query?.periodMonth),
      status: req.query?.status || null,
      limit: Number(req.query?.limit || 200),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function createSalaryAction(req, res, next) {
  try {
    const v = validateCreateSalaryAction(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.createSalaryAction(actorFromReq(req), v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function updateSalaryActionStatus(req, res, next) {
  try {
    const v = validateUpdateSalaryActionStatus(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.updateSalaryActionStatus(
      actorFromReq(req),
      Number(req.params.actionId),
      v.value
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function attendanceArchive(req, res, next) {
  try {
    const out = await service.getAttendanceArchive(actorFromReq(req), {
      merchantId: toIntOrNull(req.query?.merchantId),
      periodYear: toIntOrNull(req.query?.periodYear),
      periodMonth: toIntOrNull(req.query?.periodMonth),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function myProfiles(req, res, next) {
  try {
    const out = await service.listMyEmployeeProfiles(actorFromReq(req), {
      merchantId: toIntOrNull(req.query?.merchantId),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listMyAttendance(req, res, next) {
  try {
    const out = await service.listMyAttendance(actorFromReq(req), {
      merchantId: toIntOrNull(req.query?.merchantId),
      dateFrom: req.query?.dateFrom || null,
      dateTo: req.query?.dateTo || null,
      limit: Number(req.query?.limit || 200),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listMyLeaveRequests(req, res, next) {
  try {
    const out = await service.listMyLeaveRequests(actorFromReq(req), {
      merchantId: toIntOrNull(req.query?.merchantId),
      status: req.query?.status || null,
      limit: Number(req.query?.limit || 120),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function createMyLeaveRequest(req, res, next) {
  try {
    const v = validateCreateMyLeaveRequest(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.createMyLeaveRequest(actorFromReq(req), v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listAdvanceRequests(req, res, next) {
  try {
    const out = await service.listAdvanceRequests(actorFromReq(req), {
      merchantId: toIntOrNull(req.query?.merchantId),
      employeeUserId: toIntOrNull(req.query?.employeeUserId),
      status: req.query?.status || null,
      limit: Number(req.query?.limit || 120),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listMyAdvanceRequests(req, res, next) {
  try {
    const out = await service.listMyAdvanceRequests(actorFromReq(req), {
      merchantId: toIntOrNull(req.query?.merchantId),
      status: req.query?.status || null,
      limit: Number(req.query?.limit || 120),
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function createMyAdvanceRequest(req, res, next) {
  try {
    const v = validateCreateAdvanceRequest(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.createMyAdvanceRequest(actorFromReq(req), v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function decideAdvanceRequest(req, res, next) {
  try {
    const v = validateDecideAdvanceRequest(req.body || {});
    if (!v.ok) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: v.errors,
      });
    }
    const out = await service.decideAdvanceRequest(
      actorFromReq(req),
      Number(req.params.requestId),
      v.value
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}
