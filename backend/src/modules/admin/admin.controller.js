import * as service from "./admin.service.js";
import {
  validateAdBoardCreate,
  validateAdBoardUpdate,
  validateAdminCreateStore,
  validateAdminCreateTaxiCaptain,
  validateAdminCreateUser,
  validateApproveSettlement,
  validateDeliveryDriverProfilePatch,
  validateListResidenceChangeRequestsQuery,
  validateListSocialReportsQuery,
  validateListSocialUsersQuery,
  validateListSocialStoryReportsQuery,
  validatePostReportReview,
  validateResidenceChangeReview,
  validateSocialUserAccountStatusPatch,
  validateSocialCapabilityRestrictionCreate,
  validateAdminMerchantProfilePatch,
  validateStoreActivityUpsert,
  validateStoreCatalogTemplatePatch,
  validateStoreCatalogTemplateUpsert,
  validateTaxiCaptainCashPaymentApprove,
  validateTaxiCaptainDiscount,
  validateTaxiCaptainProfileEditReview,
  validateToggleMerchantDisabled,
} from "./admin.validators.js";
import {
  validateBillingProfilePatch,
  validateMerchantFinancialApprovalTerms,
} from "../commerce/commerce.validators.js";
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

    const user = await service.createManagedUser(body, {
      id: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin === true,
    });
    res.status(201).json({ user });
  } catch (e) {
    next(e);
  }
}

// إنشاء حساب متجر كامل من قبل الإدمن (اعتماد تلقائي + شروط مالية inline).
export async function createStoreAccount(req, res, next) {
  try {
    const body = {
      ...req.body,
      merchantImageUrl:
        buildUploadedFileUrl(req, req.file) || req.body?.merchantImageUrl,
    };

    const v = validateAdminCreateStore(body);
    if (!v.ok) {
      return res
        .status(400)
        .json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    // تُطبَّق قيم افتراضية معقولة للشروط المالية غير المُدخَلة.
    const terms = validateMerchantFinancialApprovalTerms(
      req.body?.financialTerms || {}
    );
    if (!terms.ok) {
      return res
        .status(400)
        .json({ message: "VALIDATION_ERROR", fields: terms.errors });
    }

    const out = await service.createStoreAccountByAdmin(
      { ...body, financialTerms: terms.data },
      {
        id: req.userId,
        role: req.userRole,
        isSuperAdmin: req.userIsSuperAdmin === true,
      }
    );
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

// إنشاء حساب كابتن تكسي من قبل الإدمن (اعتماد تلقائي).
export async function createTaxiCaptainAccount(req, res, next) {
  try {
    const files = req.files || {};
    const profileImageUrl =
      buildUploadedFileUrl(req, files.profileImageFile?.[0]) ||
      req.body?.profileImageUrl;
    const carImageUrl =
      buildUploadedFileUrl(req, files.carImageFile?.[0]) ||
      req.body?.carImageUrl;
    const body = {
      ...req.body,
      profileImageUrl,
      carImageUrl,
    };

    const v = validateAdminCreateTaxiCaptain(body);
    if (!v.ok) {
      return res
        .status(400)
        .json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.createTaxiCaptainAccountByAdmin(body, {
      id: req.userId,
      role: req.userRole,
      isSuperAdmin: req.userIsSuperAdmin === true,
    });
    res.status(201).json(out);
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

export async function approvalInbox(req, res, next) {
  try {
    const out = await service.listApprovalInbox(req.query || {});
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function auditFeed(req, res, next) {
  try {
    const out = await service.listAdminAuditFeed(req.query || {});
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function customerInsightsList(req, res, next) {
  try {
    const out = await service.listCustomerInsights(req.query || {});
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function customerInsightDetails(req, res, next) {
  try {
    const out = await service.getCustomerInsightDetails(req.params.customerUserId);
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

export async function adminOrdersOverview(req, res, next) {
  try {
    const out = await service.getAdminOrdersOverview(req.query || {});
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function adminMerchantOrdersOverview(req, res, next) {
  try {
    const out = await service.getAdminMerchantOrdersOverview(
      req.params.merchantId,
      req.query || {}
    );
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

export async function updateMerchantProfile(req, res, next) {
  try {
    const v = validateAdminMerchantProfilePatch(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.updateManagedMerchantProfile(
      req.params.merchantId,
      v.value,
      {
        userId: req.userId,
        userRole: req.userRole,
      }
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function storeActivities(req, res, next) {
  try {
    const out = await service.listStoreActivitiesForAdmin();
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function upsertStoreActivity(req, res, next) {
  try {
    const body = {
      ...req.body,
      activityType: req.params.activityType || req.body?.activityType,
    };
    const v = validateStoreActivityUpsert(body, { requireCode: true });
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.upsertStoreActivityForAdmin(v.value, {
      userId: req.userId,
      userRole: req.userRole,
    });
    res.status(req.method === "POST" ? 201 : 200).json(out);
  } catch (e) {
    next(e);
  }
}

export async function storeCatalogTemplates(req, res, next) {
  try {
    const out = await service.listStoreCatalogTemplatesForAdmin(
      req.params.activityType
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function upsertStoreCatalogTemplate(req, res, next) {
  try {
    const body = {
      ...req.body,
      activityType: req.params.activityType || req.body?.activityType,
    };
    const v = validateStoreCatalogTemplateUpsert(body, { requireCode: true });
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.upsertStoreCatalogTemplateForAdmin(v.value, {
      userId: req.userId,
      userRole: req.userRole,
    });
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function updateStoreCatalogTemplate(req, res, next) {
  try {
    const v = validateStoreCatalogTemplatePatch(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.updateStoreCatalogTemplateForAdmin(
      req.params.templateId,
      v.value,
      {
        userId: req.userId,
        userRole: req.userRole,
      }
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function deleteStoreCatalogTemplate(req, res, next) {
  try {
    const out = await service.deleteStoreCatalogTemplateForAdmin(
      req.params.templateId,
      {
        userId: req.userId,
        userRole: req.userRole,
      }
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function approveMerchant(req, res, next) {
  try {
    const v = validateMerchantFinancialApprovalTerms(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    await service.approveMerchant(req.params.merchantId, {
      userId: req.userId,
      userRole: req.userRole,
    }, v.data);
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

export async function pendingDeliveryAccounts(req, res, next) {
  try {
    const out = await service.listPendingDeliveryAccounts();
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function pendingTaxiCaptainAccounts(req, res, next) {
  try {
    const out = await service.listPendingTaxiCaptainAccounts();
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function approveDeliveryAccount(req, res, next) {
  try {
    const out = await service.approveDeliveryAccount(
      req.params.deliveryUserId,
      {
        userId: req.userId,
        userRole: req.userRole,
      }
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function approveTaxiCaptainAccount(req, res, next) {
  try {
    const out = await service.approveTaxiCaptainAccount(
      req.params.captainUserId,
      {
        userId: req.userId,
        userRole: req.userRole,
      }
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function updateDeliveryDriverProfile(req, res, next) {
  try {
    const v = validateDeliveryDriverProfilePatch(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.updateDeliveryDriverProfile({
      deliveryUserId: req.params.deliveryUserId,
      actor: {
        userId: req.userId,
        userRole: req.userRole,
      },
      driverType: v.value.driverType,
      merchantId: v.value.merchantId,
    });
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
      {
        userId: req.userId,
        userRole: req.userRole,
      },
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
      {
        userId: req.userId,
        userRole: req.userRole,
      }
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function pendingTaxiCaptainCashPayments(req, res, next) {
  try {
    const out = await service.listPendingTaxiCaptainCashPayments(req.query || {});
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function confirmTaxiCaptainCashPayment(req, res, next) {
  try {
    const v = validateTaxiCaptainCashPaymentApprove(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.confirmTaxiCaptainCashPayment({
      captainUserId: req.params.captainUserId,
      cycleDays: v.value.cycleDays,
      adminUserId: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function setTaxiCaptainDiscount(req, res, next) {
  try {
    const v = validateTaxiCaptainDiscount(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.setTaxiCaptainDiscount({
      captainUserId: req.params.captainUserId,
      discountPercent: v.value.discountPercent,
      adminUserId: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function pendingTaxiCaptainProfileEditRequests(req, res, next) {
  try {
    const out = await service.listPendingTaxiCaptainProfileEditRequests(req.query || {});
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function approveTaxiCaptainProfileEditRequest(req, res, next) {
  try {
    const v = validateTaxiCaptainProfileEditReview(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.approveTaxiCaptainProfileEditRequest({
      requestId: req.params.requestId,
      adminUserId: {
        userId: req.userId,
        userRole: req.userRole,
      },
      adminNote: v.value.adminNote,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function rejectTaxiCaptainProfileEditRequest(req, res, next) {
  try {
    const v = validateTaxiCaptainProfileEditReview(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.rejectTaxiCaptainProfileEditRequest({
      requestId: req.params.requestId,
      adminUserId: {
        userId: req.userId,
        userRole: req.userRole,
      },
      adminNote: v.value.adminNote,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function socialPostReports(req, res, next) {
  try {
    const v = validateListSocialReportsQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.listSocialPostReports(v.value);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function socialUserReports(req, res, next) {
  try {
    const v = validateListSocialReportsQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.listSocialUserReports(v.value);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function socialStoryReports(req, res, next) {
  try {
    const v = validateListSocialStoryReportsQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.listSocialStoryReports(v.value);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function reviewSocialPostReport(req, res, next) {
  try {
    const v = validatePostReportReview(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.reviewSocialPostReport({
      postId: req.params.postId,
      action: v.value.action,
      note: v.value.note,
      actor: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function reviewSocialStoryReport(req, res, next) {
  try {
    const v = validatePostReportReview(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.reviewSocialStoryReport({
      storyId: req.params.storyId,
      action: v.value.action,
      note: v.value.note,
      actor: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function approveEditedSocialPost(req, res, next) {
  try {
    const out = await service.approveEditedSocialPost({
      postId: req.params.postId,
      actor: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function approveEditedSocialStory(req, res, next) {
  try {
    const out = await service.approveEditedSocialStory({
      storyId: req.params.storyId,
      actor: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function residenceChangeRequests(req, res, next) {
  try {
    const v = validateListResidenceChangeRequestsQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.listResidenceChangeRequests(v.value);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function profileCoreChangeRequests(req, res, next) {
  try {
    const v = validateListResidenceChangeRequestsQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.listProfileCoreChangeRequests(v.value);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function approveResidenceChangeRequest(req, res, next) {
  try {
    const v = validateResidenceChangeReview(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.approveResidenceChangeRequest({
      requestId: req.params.requestId,
      reviewNote: v.value.reviewNote,
      actor: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function rejectResidenceChangeRequest(req, res, next) {
  try {
    const v = validateResidenceChangeReview(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.rejectResidenceChangeRequest({
      requestId: req.params.requestId,
      reviewNote: v.value.reviewNote,
      actor: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function approveProfileCoreChangeRequest(req, res, next) {
  try {
    const v = validateResidenceChangeReview(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.approveProfileCoreChangeRequest({
      requestId: req.params.requestId,
      reviewNote: v.value.reviewNote,
      actor: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function rejectProfileCoreChangeRequest(req, res, next) {
  try {
    const v = validateResidenceChangeReview(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.rejectProfileCoreChangeRequest({
      requestId: req.params.requestId,
      reviewNote: v.value.reviewNote,
      actor: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function socialRestrictionsForUser(req, res, next) {
  try {
    const out = await service.listSocialCapabilityRestrictionsForUser(
      req.params.userId
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function socialUsersForModeration(req, res, next) {
  try {
    const v = validateListSocialUsersQuery(req.query || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.listSocialUsersForModeration(v.value);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function setSocialUserAccountStatus(req, res, next) {
  try {
    const body = validateSocialUserAccountStatusPatch(req.body || {});
    if (!body.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: body.errors });
    }
    const out = await service.setSocialUserAccountStatus({
      targetUserId: req.params.userId,
      isDisabled: body.value.isDisabled,
      note: body.value.note,
      actor: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function createSocialRestriction(req, res, next) {
  try {
    const v = validateSocialCapabilityRestrictionCreate(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }
    const out = await service.createSocialCapabilityRestriction({
      userId: req.params.userId,
      ...v.value,
      actor: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function revokeSocialRestriction(req, res, next) {
  try {
    const out = await service.revokeSocialCapabilityRestriction({
      restrictionId: req.params.restrictionId,
      actor: {
        userId: req.userId,
        userRole: req.userRole,
      },
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function adBoardItems(req, res, next) {
  try {
    const out = await service.listAdBoardItems();
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function createAdBoardItem(req, res, next) {
  try {
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
    };
    const v = validateAdBoardCreate(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.createAdBoardItem(v.value, {
      userId: req.userId,
      userRole: req.userRole,
    });
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function updateAdBoardItem(req, res, next) {
  try {
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
    };
    const v = validateAdBoardUpdate(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.updateAdBoardItem(
      req.params.itemId,
      v.value,
      {
        userId: req.userId,
        userRole: req.userRole,
      }
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function adBoardMerchantProducts(req, res, next) {
  try {
    const out = await service.listAdBoardMerchantProducts(
      req.params.merchantId,
      {
        limit: Number(req.query?.limit || 300),
      }
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function deleteAdBoardItem(req, res, next) {
  try {
    const out = await service.deleteAdBoardItem(req.params.itemId, {
      userId: req.userId,
      userRole: req.userRole,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}
