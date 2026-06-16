import * as service from "./company.service.js";
import {
  validateBranchRequestCreate,
  validateCompanyCampaignCreate,
  validateCompanyCreate,
  validateCompanyCouponCreate,
  validateCompanyUserCreate,
  validateCompanyPatch,
  validateInventoryItemPatch,
  validateInventorySettingsPatch,
  validateProductCopy,
} from "./company.validators.js";

function validationError(res, fields) {
  return res.status(400).json({ message: "VALIDATION_ERROR", fields });
}

export async function companyLogin(req, res, next) {
  try {
    const out = await service.loginCompany(req.body || {}, req.authDeviceContext || {});
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function companyBootstrap(req, res, next) {
  try {
    const out = await service.bootstrapCompanyPortal(req.userId);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function dashboard(req, res, next) {
  try {
    res.json(await service.getCompanyHome(req.companyId));
  } catch (error) {
    next(error);
  }
}

export async function branches(req, res, next) {
  try {
    res.json(await service.listCompanyBranches(req.companyId, req.query || {}));
  } catch (error) {
    next(error);
  }
}

export async function branchDetail(req, res, next) {
  try {
    res.json(await service.getCompanyBranchDetail(req.companyId, req.params.merchantId));
  } catch (error) {
    next(error);
  }
}

export async function listUsers(req, res, next) {
  try {
    res.json(await service.listCompanyUsers(req.companyId));
  } catch (error) {
    next(error);
  }
}

export async function createUser(req, res, next) {
  try {
    const v = validateCompanyUserCreate(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    res.status(201).json(await service.createCompanyUser(req.companyId, req.body || {}, {
      userId: req.userId,
      role: req.companyRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function updatePolicy(req, res, next) {
  try {
    res.json(await service.updateCompanyPolicy(req.companyId, req.body || {}, {
      userId: req.userId,
      role: req.companyRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function createBranchRequest(req, res, next) {
  try {
    const v = validateBranchRequestCreate(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    res.status(201).json(await service.createCompanyBranchRequest(req.companyId, req.body || {}, {
      userId: req.userId,
      role: req.companyRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function listBranchRequests(req, res, next) {
  try {
    res.json(await service.listCompanyBranchRequests(req.companyId, req.query || {}));
  } catch (error) {
    next(error);
  }
}

export async function copyProducts(req, res, next) {
  try {
    const v = validateProductCopy(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    res.json(await service.copyProductsBetweenBranches(req.companyId, req.body || {}, {
      userId: req.userId,
      role: req.companyRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function listCoupons(req, res, next) {
  try {
    res.json(await service.listCompanyCoupons(req.companyId));
  } catch (error) {
    next(error);
  }
}

export async function createCoupon(req, res, next) {
  try {
    const v = validateCompanyCouponCreate(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    res.status(201).json(await service.createCompanyCoupon(req.companyId, req.body || {}, {
      userId: req.userId,
      role: req.companyRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function listCampaigns(req, res, next) {
  try {
    res.json(await service.listCompanyCampaigns(req.companyId));
  } catch (error) {
    next(error);
  }
}

export async function createCampaign(req, res, next) {
  try {
    const v = validateCompanyCampaignCreate(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    res.status(201).json(await service.createCompanyCampaign(req.companyId, req.body || {}, {
      userId: req.userId,
      role: req.companyRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function inventoryOverview(req, res, next) {
  try {
    res.json(await service.getCompanyInventoryOverview(req.companyId));
  } catch (error) {
    next(error);
  }
}

export async function branchInventory(req, res, next) {
  try {
    res.json(await service.getCompanyBranchInventory(req.companyId, req.params.merchantId));
  } catch (error) {
    next(error);
  }
}

export async function patchInventorySettings(req, res, next) {
  try {
    const v = validateInventorySettingsPatch(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    res.json(await service.patchCompanyBranchInventorySettings(req.companyId, req.params.merchantId, req.body || {}, {
      userId: req.userId,
      role: req.companyRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function patchInventoryItem(req, res, next) {
  try {
    const v = validateInventoryItemPatch(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    res.json(await service.patchCompanyInventoryItem(req.companyId, req.params.merchantId, req.params.productId, req.body || {}, {
      userId: req.userId,
      role: req.companyRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function confirmDailyCheck(req, res, next) {
  try {
    res.json(await service.confirmCompanyBranchDailyCheck(req.companyId, req.params.merchantId, req.body?.note || null, {
      userId: req.userId,
      role: req.companyRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function adminListCompanies(req, res, next) {
  try {
    res.json(await service.listAdminCompanies(req.query || {}));
  } catch (error) {
    next(error);
  }
}

export async function adminCreateCompany(req, res, next) {
  try {
    const v = validateCompanyCreate(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    res.status(201).json(await service.createAdminCompany(req.body || {}, {
      userId: req.userId,
      role: req.userRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function adminUpdateCompany(req, res, next) {
  try {
    const v = validateCompanyPatch(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    res.json(await service.updateAdminCompany(req.params.companyId, req.body || {}, {
      userId: req.userId,
      role: req.userRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function adminDeleteCompany(req, res, next) {
  try {
    res.json(await service.deleteAdminCompany(req.params.companyId, {
      userId: req.userId,
      role: req.userRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function adminLinkBranch(req, res, next) {
  try {
    res.json(await service.linkAdminCompanyBranch({
      companyId: req.params.companyId,
      merchantId: req.body?.merchantId,
    }, {
      userId: req.userId,
      role: req.userRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function adminUnlinkBranch(req, res, next) {
  try {
    res.json(await service.unlinkAdminCompanyBranch({
      companyId: req.params.companyId,
      merchantId: req.params.merchantId,
    }, {
      userId: req.userId,
      role: req.userRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function adminListBranchRequests(req, res, next) {
  try {
    res.json(await service.listAdminPendingBranchRequests());
  } catch (error) {
    next(error);
  }
}

export async function adminApproveBranchRequest(req, res, next) {
  try {
    res.json(await service.approveAdminBranchRequest(req.params.requestId, req.body || {}, {
      userId: req.userId,
      role: req.userRole,
    }));
  } catch (error) {
    next(error);
  }
}

export async function adminRejectBranchRequest(req, res, next) {
  try {
    res.json(await service.rejectAdminBranchRequest(req.params.requestId, req.body || {}, {
      userId: req.userId,
      role: req.userRole,
    }));
  } catch (error) {
    next(error);
  }
}
