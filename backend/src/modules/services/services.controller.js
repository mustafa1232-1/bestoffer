import { buildUploadedFileUrl } from '../../shared/utils/upload.js';
import * as service from './services.service.js';
import {
  parseJsonPayload,
  validateAdminCategoryReviewBody,
  validateAdminOfferingStatusBody,
  validateAdminProviderStatusBody,
  validateCategorySuggestionBody,
  validateIdParam,
  validateModerationStatusQuery,
  validateAdminCashConfirmationBody,
  validateAdminSubscriptionOfferBody,
  validateAdminSubscriptionRejectBody,
  validateOfferingBody,
  validateProviderEmployeeActivityLogQuery,
  validateProviderEmployeeInviteBody,
  validateProviderEmployeeUpsertBody,
  validatePaginationQuery,
  validatePortfolioBody,
  validatePromotionBody,
  validateProviderSubscriptionOfferResponseBody,
  validateProviderSubscriptionStatusBody,
  validateProviderProfileUpdateBody,
  validateProviderRegisterBody,
  validateQuoteBody,
  validateQuoteResponseBody,
  validateRequestStatusBody,
  validateReviewBody,
  validateServiceRequestBody,
  validateServiceSearchQuery,
} from './services.validators.js';

function collectUploadedUrls(req, fieldName = null) {
  if (Array.isArray(req.files)) {
    return req.files
      .map((file) => buildUploadedFileUrl(req, file))
      .filter(Boolean);
  }
  if (req.files && typeof req.files === 'object') {
    const values = fieldName ? req.files[fieldName] : Object.values(req.files).flat();
    return (Array.isArray(values) ? values : [])
      .map((file) => buildUploadedFileUrl(req, file))
      .filter(Boolean);
  }
  return [];
}

function firstUploadedUrl(req, fieldName) {
  const urls = collectUploadedUrls(req, fieldName);
  return urls[0] || null;
}

function parseBodyJsonFields(body = {}, fields = []) {
  const out = { ...body };
  for (const field of fields) {
    if (out[field] == null) continue;
    const parsed = parseJsonPayload(out[field]);
    if (parsed != null) out[field] = parsed;
  }
  return out;
}

function validationError(res, errors) {
  return res.status(400).json({ message: 'VALIDATION_ERROR', fields: errors });
}

function deviceContextFromReq(req) {
  return {
    deviceFingerprint:
      req.authDeviceContext?.deviceFingerprint ||
      req.headers['x-device-id'] ||
      req.headers['x-installation-id'] ||
      null,
    userAgent: req.headers['user-agent'] || null,
    ipAddress: req.ip || req.connection?.remoteAddress || null,
  };
}

export async function registerProvider(req, res, next) {
  try {
    const body = parseBodyJsonFields(req.body || {}, [
      'areas',
      'availabilityRules',
      'languages',
    ]);
    const v = validateProviderRegisterBody(body);
    if (!v.ok) return validationError(res, v.errors);

    const out = await service.registerServiceProvider(
      v.value,
      {
        logoUrl: firstUploadedUrl(req, 'logoFile') || firstUploadedUrl(req, 'profileImageFile'),
        coverImageUrl: firstUploadedUrl(req, 'coverFile'),
      },
      deviceContextFromReq(req)
    );
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function getProviderSubscriptionStatus(req, res, next) {
  try {
    const v = validateProviderSubscriptionStatusBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.getProviderSubscriptionStatus(v.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function respondProviderSubscriptionOffer(req, res, next) {
  try {
    const idv = validateIdParam(req.params.requestId, 'requestId');
    if (!idv.ok) return validationError(res, idv.errors);
    const body = req.body || {};
    const statusV = validateProviderSubscriptionStatusBody(body);
    const responseV = validateProviderSubscriptionOfferResponseBody(body);
    const errors = [...statusV.errors, ...responseV.errors];
    if (errors.length) return validationError(res, errors);
    const out = await service.respondProviderSubscriptionOffer({
      requestId: idv.value,
      dto: {
        ...statusV.value,
        ...responseV.value,
      },
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listPublicCategories(req, res, next) {
  try {
    const out = await service.listPublicCategories();
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function searchPublic(req, res, next) {
  try {
    const v = validateServiceSearchQuery(req.query || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.searchPublicOfferings(v.value, req.userId || null);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function getPublicProvider(req, res, next) {
  try {
    const idv = validateIdParam(req.params.providerId, 'providerId');
    if (!idv.ok) return validationError(res, idv.errors);
    const out = await service.getPublicProvider(idv.value, req.userId || null);
    if (!out) return res.status(404).json({ message: 'SERVICE_PROVIDER_NOT_FOUND' });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function getPublicOffering(req, res, next) {
  try {
    const idv = validateIdParam(req.params.offeringId, 'offeringId');
    if (!idv.ok) return validationError(res, idv.errors);
    const out = await service.getPublicOffering(idv.value, req.userId || null);
    if (!out) return res.status(404).json({ message: 'SERVICE_OFFERING_NOT_FOUND' });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function getProviderWorkspace(req, res, next) {
  try {
    const out = await service.getProviderWorkspace({
      userId: req.userId,
      userRole: req.userRole,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function getProviderProfile(req, res, next) {
  try {
    const out = await service.getProviderProfile({
      userId: req.userId,
      userRole: req.userRole,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function updateProviderProfile(req, res, next) {
  try {
    const body = parseBodyJsonFields(req.body || {}, [
      'areas',
      'availabilityRules',
      'languages',
    ]);
    const v = validateProviderProfileUpdateBody(body);
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.updateProviderProfile({
      userId: req.userId,
      userRole: req.userRole,
      dto: v.value,
      assets: {
        logoUrl: firstUploadedUrl(req, 'logoFile') || null,
        coverImageUrl: firstUploadedUrl(req, 'coverFile') || null,
      },
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listProviderEmployees(req, res, next) {
  try {
    const v = validatePaginationQuery(req.query || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.listProviderEmployees(
      { userId: req.userId, userRole: req.userRole },
      {
        search: req.query?.search || '',
        limit: v.value.limit,
      }
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function inviteProviderEmployee(req, res, next) {
  try {
    const v = validateProviderEmployeeInviteBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.inviteProviderEmployee(
      { userId: req.userId, userRole: req.userRole },
      v.value
    );
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function upsertProviderEmployee(req, res, next) {
  try {
    const v = validateProviderEmployeeUpsertBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.upsertProviderEmployee(
      { userId: req.userId, userRole: req.userRole },
      v.value
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listProviderEmployeeActivityLogs(req, res, next) {
  try {
    const v = validateProviderEmployeeActivityLogQuery(req.query || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.listProviderEmployeeActivityLogs(
      { userId: req.userId, userRole: req.userRole },
      v.value
    );
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function createOffering(req, res, next) {
  try {
    const body = parseBodyJsonFields(req.body || {}, ['pricingOptions']);
    const v = validateOfferingBody(body);
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.createOffering({
      userId: req.userId,
      userRole: req.userRole,
      dto: v.value,
      mediaUrls: collectUploadedUrls(req, 'mediaFiles'),
    });
    res.status(201).json({ offering: out });
  } catch (error) {
    next(error);
  }
}

export async function updateOffering(req, res, next) {
  try {
    const idv = validateIdParam(req.params.offeringId, 'offeringId');
    if (!idv.ok) return validationError(res, idv.errors);
    const body = parseBodyJsonFields(req.body || {}, ['pricingOptions']);
    const v = validateOfferingBody(body, { partial: true });
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.updateOffering({
      userId: req.userId,
      userRole: req.userRole,
      offeringId: idv.value,
      dto: v.value,
      mediaUrls: collectUploadedUrls(req, 'mediaFiles'),
    });
    res.json({ offering: out });
  } catch (error) {
    next(error);
  }
}

export async function replaceOfferingPricing(req, res, next) {
  try {
    const idv = validateIdParam(req.params.offeringId, 'offeringId');
    if (!idv.ok) return validationError(res, idv.errors);
    const body = parseBodyJsonFields(req.body || {}, ['pricingOptions']);
    const options = Array.isArray(body.pricingOptions) ? body.pricingOptions : [];
    const out = await service.replaceOfferingPricing({
      userId: req.userId,
      userRole: req.userRole,
      offeringId: idv.value,
      pricingOptions: options,
    });
    res.json({ offering: out });
  } catch (error) {
    next(error);
  }
}

export async function createPromotion(req, res, next) {
  try {
    const body = parseBodyJsonFields(req.body || {}, ['offeringIds']);
    const v = validatePromotionBody(body);
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.createPromotion({
      userId: req.userId,
      userRole: req.userRole,
      dto: v.value,
    });
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function createPortfolioItem(req, res, next) {
  try {
    const body = req.body || {};
    const v = validatePortfolioBody(body);
    if (!v.ok) return validationError(res, v.errors);
    const mediaUrl = firstUploadedUrl(req, 'mediaFile');
    const out = await service.createPortfolioItem({
      userId: req.userId,
      userRole: req.userRole,
      dto: v.value,
      mediaUrl,
    });
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function deletePortfolioItem(req, res, next) {
  try {
    const idv = validateIdParam(req.params.portfolioId, 'portfolioId');
    if (!idv.ok) return validationError(res, idv.errors);
    const out = await service.deletePortfolioItem({
      userId: req.userId,
      userRole: req.userRole,
      portfolioId: idv.value,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function createCategorySuggestion(req, res, next) {
  try {
    const v = validateCategorySuggestionBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.createCategorySuggestion({
      userId: req.userId,
      userRole: req.userRole,
      dto: v.value,
    });
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function listMyCategorySuggestions(req, res, next) {
  try {
    const p = validatePaginationQuery(req.query || {});
    const out = await service.listMyCategorySuggestions({
      userId: req.userId,
      userRole: req.userRole,
      query: p.value,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listProviderRequests(req, res, next) {
  try {
    const p = validatePaginationQuery(req.query || {});
    const out = await service.listProviderRequests({
      userId: req.userId,
      userRole: req.userRole,
      query: { ...p.value, status: req.query?.status || null },
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function createQuote(req, res, next) {
  try {
    const idv = validateIdParam(req.params.requestId, 'requestId');
    if (!idv.ok) return validationError(res, idv.errors);
    const v = validateQuoteBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.createQuote({
      userId: req.userId,
      userRole: req.userRole,
      requestId: idv.value,
      dto: v.value,
    });
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function updateProviderRequestStatus(req, res, next) {
  try {
    const idv = validateIdParam(req.params.requestId, 'requestId');
    if (!idv.ok) return validationError(res, idv.errors);
    const v = validateRequestStatusBody(req.body || {}, { providerFlow: true });
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.updateRequestStatusByProvider({
      userId: req.userId,
      userRole: req.userRole,
      requestId: idv.value,
      dto: v.value,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function createServiceRequest(req, res, next) {
  try {
    const body = req.body || {};
    const v = validateServiceRequestBody(body);
    if (!v.ok) return validationError(res, v.errors);
    const attachments = collectUploadedUrls(req, 'attachmentFiles').map((url) => ({
      mediaUrl: url,
      mediaKind: 'image',
    }));
    const out = await service.createServiceRequest({
      userId: req.userId,
      dto: v.value,
      attachments,
    });
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function listMyRequests(req, res, next) {
  try {
    const p = validatePaginationQuery(req.query || {});
    const out = await service.listMyRequests({
      userId: req.userId,
      query: { ...p.value, status: req.query?.status || null },
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function getMyRequest(req, res, next) {
  try {
    const idv = validateIdParam(req.params.requestId, 'requestId');
    if (!idv.ok) return validationError(res, idv.errors);
    const out = await service.getMyRequest({
      userId: req.userId,
      requestId: idv.value,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function updateMyRequestStatus(req, res, next) {
  try {
    const idv = validateIdParam(req.params.requestId, 'requestId');
    if (!idv.ok) return validationError(res, idv.errors);
    const v = validateRequestStatusBody(req.body || {}, { providerFlow: false });
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.updateRequestStatusByCustomer({
      userId: req.userId,
      requestId: idv.value,
      dto: v.value,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function respondToQuote(req, res, next) {
  try {
    const requestIdV = validateIdParam(req.params.requestId, 'requestId');
    if (!requestIdV.ok) return validationError(res, requestIdV.errors);
    const quoteIdV = validateIdParam(req.params.quoteId, 'quoteId');
    if (!quoteIdV.ok) return validationError(res, quoteIdV.errors);
    const v = validateQuoteResponseBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.respondToQuote({
      userId: req.userId,
      requestId: requestIdV.value,
      quoteId: quoteIdV.value,
      dto: v.value,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function createReview(req, res, next) {
  try {
    const v = validateReviewBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.createReview({
      userId: req.userId,
      dto: v.value,
    });
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function listProviderReviews(req, res, next) {
  try {
    const idv = validateIdParam(req.params.providerId, 'providerId');
    if (!idv.ok) return validationError(res, idv.errors);
    const p = validatePaginationQuery(req.query || {});
    const out = await service.listProviderReviews(idv.value, p.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listOfferingReviews(req, res, next) {
  try {
    const idv = validateIdParam(req.params.offeringId, 'offeringId');
    if (!idv.ok) return validationError(res, idv.errors);
    const p = validatePaginationQuery(req.query || {});
    const out = await service.listOfferingReviews(idv.value, p.value);
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function saveProvider(req, res, next) {
  try {
    const idv = validateIdParam(req.params.providerId, 'providerId');
    if (!idv.ok) return validationError(res, idv.errors);
    const out = await service.saveProvider({
      userId: req.userId,
      providerId: idv.value,
    });
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function unsaveProvider(req, res, next) {
  try {
    const idv = validateIdParam(req.params.providerId, 'providerId');
    if (!idv.ok) return validationError(res, idv.errors);
    const out = await service.unsaveProvider({
      userId: req.userId,
      providerId: idv.value,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function saveOffering(req, res, next) {
  try {
    const idv = validateIdParam(req.params.offeringId, 'offeringId');
    if (!idv.ok) return validationError(res, idv.errors);
    const out = await service.saveOffering({
      userId: req.userId,
      offeringId: idv.value,
    });
    res.status(201).json(out);
  } catch (error) {
    next(error);
  }
}

export async function unsaveOffering(req, res, next) {
  try {
    const idv = validateIdParam(req.params.offeringId, 'offeringId');
    if (!idv.ok) return validationError(res, idv.errors);
    const out = await service.unsaveOffering({
      userId: req.userId,
      offeringId: idv.value,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listSavedProviders(req, res, next) {
  try {
    const p = validatePaginationQuery(req.query || {});
    const out = await service.listSavedProviders({
      userId: req.userId,
      query: p.value,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listSavedOfferings(req, res, next) {
  try {
    const p = validatePaginationQuery(req.query || {});
    const out = await service.listSavedOfferings({
      userId: req.userId,
      query: p.value,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listRecentViews(req, res, next) {
  try {
    const p = validatePaginationQuery(req.query || {});
    const out = await service.listRecentViews({
      userId: req.userId,
      query: { limit: p.value.limit },
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listPendingProviders(req, res, next) {
  try {
    const p = validatePaginationQuery(req.query || {});
    const m = validateModerationStatusQuery(req.query || {});
    const out = await service.listPendingProviders({
      query: { ...p.value, ...m.value },
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listProviderSubscriptionRequests(req, res, next) {
  try {
    const p = validatePaginationQuery(req.query || {});
    const m = validateModerationStatusQuery(req.query || {});
    const out = await service.listProviderSubscriptionRequestsForAdmin({
      query: {
        ...p.value,
        ...m.value,
        search: req.query?.search || null,
      },
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminSendSubscriptionOffer(req, res, next) {
  try {
    const idv = validateIdParam(req.params.requestId, 'requestId');
    if (!idv.ok) return validationError(res, idv.errors);
    const v = validateAdminSubscriptionOfferBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.adminSendProviderSubscriptionOffer({
      requestId: idv.value,
      dto: v.value,
      adminUserId: req.userId,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminRejectSubscriptionRequest(req, res, next) {
  try {
    const idv = validateIdParam(req.params.requestId, 'requestId');
    if (!idv.ok) return validationError(res, idv.errors);
    const v = validateAdminSubscriptionRejectBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.adminRejectProviderSubscriptionRequest({
      requestId: idv.value,
      dto: v.value,
      adminUserId: req.userId,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminConfirmSubscriptionCashPayment(req, res, next) {
  try {
    const idv = validateIdParam(req.params.requestId, 'requestId');
    if (!idv.ok) return validationError(res, idv.errors);
    const v = validateAdminCashConfirmationBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.adminConfirmProviderSubscriptionCashPayment({
      requestId: idv.value,
      dto: v.value,
      adminUserId: req.userId,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminUpdateProviderStatus(req, res, next) {
  try {
    const idv = validateIdParam(req.params.providerId, 'providerId');
    if (!idv.ok) return validationError(res, idv.errors);
    const v = validateAdminProviderStatusBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.adminUpdateProviderStatus({
      providerId: idv.value,
      dto: v.value,
      adminUserId: req.userId,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listOfferingsForAdmin(req, res, next) {
  try {
    const p = validatePaginationQuery(req.query || {});
    const m = validateModerationStatusQuery(req.query || {});
    const out = await service.listOfferingsForAdmin({
      query: { ...p.value, ...m.value },
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminUpdateOfferingStatus(req, res, next) {
  try {
    const idv = validateIdParam(req.params.offeringId, 'offeringId');
    if (!idv.ok) return validationError(res, idv.errors);
    const v = validateAdminOfferingStatusBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.adminUpdateOfferingStatus({
      offeringId: idv.value,
      dto: v.value,
      adminUserId: req.userId,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listCategorySuggestionsForAdmin(req, res, next) {
  try {
    const p = validatePaginationQuery(req.query || {});
    const m = validateModerationStatusQuery(req.query || {});
    const out = await service.listCategorySuggestionsForAdmin({
      query: { ...p.value, ...m.value },
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminReviewCategorySuggestion(req, res, next) {
  try {
    const idv = validateIdParam(req.params.suggestionId, 'suggestionId');
    if (!idv.ok) return validationError(res, idv.errors);
    const v = validateAdminCategoryReviewBody(req.body || {});
    if (!v.ok) return validationError(res, v.errors);
    const out = await service.adminReviewCategorySuggestion({
      suggestionId: idv.value,
      dto: v.value,
      adminUserId: req.userId,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listServiceReportsForAdmin(req, res, next) {
  try {
    const p = validatePaginationQuery(req.query || {});
    const out = await service.listServiceReportsForAdmin({
      query: { ...p.value, status: req.query?.status || 'pending' },
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function adminReviewReport(req, res, next) {
  try {
    const idv = validateIdParam(req.params.reportId, 'reportId');
    if (!idv.ok) return validationError(res, idv.errors);
    const status = String(req.body?.status || '').trim().toLowerCase();
    if (!['resolved', 'rejected', 'pending'].includes(status)) {
      return validationError(res, ['status']);
    }
    const out = await service.adminReviewReport({
      reportId: idv.value,
      dto: { status, reviewNote: req.body?.reviewNote || null },
      adminUserId: req.userId,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listRequestsForAdmin(req, res, next) {
  try {
    const p = validatePaginationQuery(req.query || {});
    const m = validateModerationStatusQuery(req.query || {});
    const out = await service.listRequestsForAdmin({
      query: { ...p.value, ...m.value },
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function getAdminDashboardStats(req, res, next) {
  try {
    const out = await service.getAdminDashboardStats();
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function listModuleSettings(req, res, next) {
  try {
    const out = await service.listModuleSettings();
    res.json(out);
  } catch (error) {
    next(error);
  }
}

export async function upsertModuleSetting(req, res, next) {
  try {
    const key = String(req.body?.key || '').trim();
    if (!key) return validationError(res, ['key']);
    const value = parseJsonPayload(req.body?.value) || req.body?.value || {};
    const out = await service.upsertModuleSetting({
      key,
      value,
      adminUserId: req.userId,
    });
    res.json(out);
  } catch (error) {
    next(error);
  }
}
