import * as service from "./admin.service.js";
import {
  validateAdminCreateUser,
  validateApproveSettlement,
  validateToggleMerchantDisabled,
} from "./admin.validators.js";
import { buildUploadedFileUrl } from "../../shared/utils/upload.js";

export async function createUser(req, res, next) {
  try {
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
    };

    const v = validateAdminCreateUser(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const user = await service.createManagedUser(body);
    res.status(201).json({ user });
  } catch (e) {
    next(e);
  }
}

export async function availableOwners(req, res, next) {
  try {
    const owners = await service.listAvailableOwners();
    res.json(owners);
  } catch (e) {
    next(e);
  }
}

export async function analytics(req, res, next) {
  try {
    const out = await service.getAnalytics();
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function printOrdersReport(req, res, next) {
  try {
    const out = await service.printOrdersReport(req.query?.period);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function pendingMerchants(req, res, next) {
  try {
    const out = await service.getPendingMerchants();
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function merchants(req, res, next) {
  try {
    const out = await service.listMerchants();
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function approveMerchant(req, res, next) {
  try {
    await service.approveMerchant(req.params.merchantId, req.userId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function pendingSettlements(req, res, next) {
  try {
    const out = await service.getPendingSettlements();
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function approveSettlement(req, res, next) {
  try {
    const v = validateApproveSettlement(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    await service.approveSettlement(
      req.params.settlementId,
      req.userId,
      req.body?.adminNote
    );
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

export async function toggleMerchantDisabled(req, res, next) {
  try {
    const v = validateToggleMerchantDisabled(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.toggleMerchantDisabled(
      req.params.merchantId,
      req.body?.isDisabled,
      req.userId
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}
