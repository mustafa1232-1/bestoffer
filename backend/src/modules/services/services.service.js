import { AppError } from '../../shared/utils/errors.js';
import { hashPin, verifyPinDetailed } from '../../shared/utils/hash.js';
import {
  createUser,
  findUserByPhone,
} from '../auth/auth.repo.js';
import { runWithGeneratedAppUserUsername } from '../auth/auth.service.js';
import {
  createManyNotifications,
  createNotification,
} from '../notifications/notifications.repo.js';
import { listBackofficeUserIds } from '../paid-upgrades/paid-upgrades.repo.js';
import {
  PRICING_MODE_TO_CTA,
  SERVICE_PRICING_MODELS,
} from './services.constants.js';
import * as repo from './services.repo.js';
import {
  buildWorkspacePermissionPayload,
  hasPermission,
  SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS,
} from '../../shared/workspaces/employee-permissions.js';

function normalizeDigits(value) {
  return String(value || '')
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

function normalizePhone(value) {
  const digits = normalizeDigits(value).replace(/[^\d]/g, '');
  if (digits.startsWith('00964') && digits.length >= 14) {
    return `0${digits.slice(5)}`;
  }
  if (digits.startsWith('964') && digits.length >= 13) {
    return `0${digits.slice(3)}`;
  }
  if (digits.startsWith('7') && digits.length === 10) {
    return `0${digits}`;
  }
  return digits;
}

function normalizePin(value) {
  return normalizeDigits(value).replace(/[^\d]/g, '');
}

function normalizeRole(value) {
  return String(value || '').trim().toLowerCase();
}

function toActorUserId(actor) {
  const id = Number(actor?.userId || 0);
  if (!Number.isInteger(id) || id <= 0) {
    throw new AppError('UNAUTHORIZED', { status: 401 });
  }
  return id;
}

function mapProviderEmployeeProfileRow(row) {
  if (!row) return null;
  const payload = buildWorkspacePermissionPayload(
    row.permissions_json,
    'service_provider'
  );
  return {
    id: Number(row.id),
    roleTag: row.role_tag || 'staff',
    displayName: row.display_name || null,
    contactEmail: row.contact_email || null,
    permissions: payload.permissions,
    permissionMap: payload.permissionMap,
    isActive: row.is_active !== false,
    archivedAt: row.archived_at || null,
    notes: row.notes || null,
    invitedByUserId:
      row.invited_by_user_id == null ? null : Number(row.invited_by_user_id),
    updatedByUserId:
      row.updated_by_user_id == null ? null : Number(row.updated_by_user_id),
  };
}

function mapProviderEmployeeRow(row) {
  if (!row) return null;
  return {
    userId: Number(row.id),
    fullName: row.full_name || '',
    phone: row.phone || '',
    role: row.role || 'service_provider',
    imageUrl: row.image_url || null,
    displayName: row.display_name || row.full_name || null,
    contactEmail: row.contact_email || null,
    profile: row.employee_profile_id ? mapProviderEmployeeProfileRow(row) : null,
  };
}

function mapProviderEmployeeActivityLog(row) {
  return {
    id: Number(row.id),
    workspaceKind: row.workspace_kind || 'service_provider',
    workspaceId: Number(row.workspace_id),
    employeeProfileId:
      row.employee_profile_id == null ? null : Number(row.employee_profile_id),
    employeeUserId: Number(row.employee_user_id),
    employeeFullName: row.employee_full_name || '',
    employeePhone: row.employee_phone || '',
    actorUserId: row.actor_user_id == null ? null : Number(row.actor_user_id),
    actorFullName: row.actor_full_name || null,
    actorRole: row.actor_role || '',
    actionKey: row.action_key || '',
    reason: row.reason || null,
    oldValue:
      row.old_value && typeof row.old_value === 'object' ? row.old_value : {},
    newValue:
      row.new_value && typeof row.new_value === 'object' ? row.new_value : {},
    note: row.note || null,
    createdAt: row.created_at || null,
  };
}

const FREE_PROVIDER_APPLICATION_STATES = new Set([
  'not_submitted',
  'draft',
  'submitted',
  'under_review',
  'approved',
  'rejected',
  'suspended',
]);

const LEGACY_PROVIDER_PAYMENT_STATES = new Set([
  'pending_offer',
  'offer_sent',
  'offer_accepted',
  'offer_rejected',
  'payment_pending_confirmation',
  'payment_confirmed',
  'account_created',
  'cancelled',
]);

function normalizeProviderApplicationState(value) {
  const status = String(value || '').trim().toLowerCase();
  switch (status) {
    case 'pending':
    case 'pending_review':
    case 'submitted':
    case 'under_review':
      return 'under_review';
    case 'approved':
      return 'approved';
    case 'rejected':
      return 'rejected';
    case 'suspended':
      return 'suspended';
    case 'draft':
      return 'draft';
    case 'not_submitted':
      return 'not_submitted';
    default:
      return LEGACY_PROVIDER_PAYMENT_STATES.has(status)
        ? 'under_review'
        : 'under_review';
  }
}

function mapFreeProviderApplicationProgress({
  provider = null,
  submitted = false,
  reusedExistingApplication = false,
  legacyRequest = null,
}) {
  const legacyStatus = legacyRequest
    ? String(legacyRequest.status || '').trim().toLowerCase()
    : '';
  const hasLegacyPaymentState = LEGACY_PROVIDER_PAYMENT_STATES.has(legacyStatus);
  const status = provider
    ? normalizeProviderApplicationState(provider.providerApprovalStatus)
    : submitted
      ? 'submitted'
      : normalizeProviderApplicationState(legacyStatus || 'not_submitted');
  const normalizedStatus = FREE_PROVIDER_APPLICATION_STATES.has(status)
    ? status
    : 'under_review';
  const nextAction =
    normalizedStatus === 'approved'
      ? 'login_available'
      : normalizedStatus === 'rejected'
        ? 'review_rejection_reason'
        : normalizedStatus === 'suspended'
          ? 'contact_support'
          : 'wait_admin_review';

  return {
    application: provider
      ? {
          id: provider.id,
          applicationCode: `SP-${provider.id}`,
          businessName: provider.businessName || '',
          phone: provider.phone || '',
          providerApprovalStatus: provider.providerApprovalStatus || 'pending',
          approvalNote: provider.approvalNote || null,
        }
      : legacyRequest
        ? {
            id: legacyRequest.id,
            applicationCode: legacyRequest.requestCode || '',
            businessName: legacyRequest.businessName || '',
            phone: legacyRequest.phone || '',
            legacyStatus,
            approvalNote: legacyRequest.statusNote || null,
          }
        : null,
    status: normalizedStatus,
    nextAction,
    canLogin: normalizedStatus === 'approved',
    requiresProviderAction: false,
    reusedExistingApplication,
    compatibilityWarning: hasLegacyPaymentState,
  };
}

function pricingCta(pricingModel) {
  const key = String(pricingModel || '').trim().toLowerCase();
  return PRICING_MODE_TO_CTA[key] || 'Ø§Ø·Ù„Ø¨ Ø§Ù„Ø®Ø¯Ù…Ø©';
}

function attachPricingDisplay(item) {
  const pricing = Array.isArray(item?.pricingOptions) ? item.pricingOptions : [];
  const lead = pricing.find((x) => x.isDefault) || pricing[0] || null;
  if (!lead) {
    return {
      ...item,
      displayPriceText: 'Ø¨Ø¹Ø¯ Ø§Ù„Ù…Ø¹Ø§ÙŠÙ†Ø©',
      bookingCta: 'Ø§Ø·Ù„Ø¨ ØªØ³Ø¹ÙŠØ±',
      leadPricing: null,
    };
  }

  const model = String(lead.pricingModel || '').trim().toLowerCase();
  const amount = lead.amount == null ? null : Number(lead.amount);
  let displayPriceText = 'Ø¨Ø¹Ø¯ Ø§Ù„Ù…Ø¹Ø§ÙŠÙ†Ø©';
  if (model === 'starting_from' && amount != null) {
    displayPriceText = `ÙŠØ¨Ø¯Ø£ Ù…Ù† ${amount}`;
  } else if (['inspection_required', 'custom_quote'].includes(model)) {
    displayPriceText = model === 'inspection_required' ? 'Ø­Ø³Ø¨ Ø§Ù„Ù…Ø¹Ø§ÙŠÙ†Ø©' : 'ØªØ³Ø¹ÙŠØ± Ù…Ø®ØµØµ';
  } else if (amount != null) {
    displayPriceText = `${amount} / ${lead.pricingUnit || 'Ø®Ø¯Ù…Ø©'}`;
  }

  return {
    ...item,
    leadPricing: lead,
    displayPriceText,
    bookingCta: pricingCta(model),
  };
}

async function notifyBackoffice(payloadFactory) {
  const adminIds = await listBackofficeUserIds().catch(() => []);
  if (!Array.isArray(adminIds) || adminIds.length === 0) return;
  await createManyNotifications(
    adminIds.map((id) => payloadFactory(Number(id))).filter(Boolean)
  ).catch(() => {});
}

async function notifyOfferingModerationToProvider({
  offering,
  status,
  note = null,
}) {
  if (!offering?.providerId || !offering?.id) return;

  const provider = await repo.getProviderByIdForAdmin(offering.providerId).catch(() => null);
  if (!provider?.userId) return;

  const recipients = new Map();
  recipients.set(Number(provider.userId), {
    userId: Number(provider.userId),
    type: `services.offering.status.${String(status || 'pending').trim().toLowerCase()}`,
    title: 'تحديث على الخدمة',
    body: `${offering.name} تم تحديثها.`,
    payload: {
      target: 'services_provider_workspace',
      targetModule: 'customer',
      providerId: offering.providerId,
      offeringId: offering.id,
      requiresAction: false,
    },
  });

  const employees = await repo
    .listActiveProviderNotificationRecipients({
      providerId: offering.providerId,
      requiredPermissions: ['edit_services'],
    })
    .catch(() => []);
  for (const employee of employees) {
    if (!employee?.userId) continue;
    recipients.set(Number(employee.userId), {
      userId: Number(employee.userId),
      type: `services.offering.status.${String(status || 'pending').trim().toLowerCase()}`,
      title: 'تحديث على الخدمة',
      body: `${offering.name} تم تحديثها.`,
      payload: {
        target: 'services_provider_workspace',
        targetModule: 'customer',
        providerId: offering.providerId,
        offeringId: offering.id,
        requiresAction: false,
      },
    });
  }

  const normalizedStatus = String(status || 'pending').trim().toLowerCase();
  const titleMap = {
    approved: 'تمت الموافقة على الخدمة',
    rejected: 'تم رفض الخدمة',
    changes_requested: 'تحتاج الخدمة إلى تعديلات',
    hidden: 'تم إخفاء الخدمة',
    pending: 'تحديث على الخدمة',
  };
  const bodyMap = {
    approved: `${offering.name} أصبحت جاهزة للنشر.`,
    rejected: `${offering.name} تم رفضها. يمكنك تعديلها ثم إعادة إرسالها للمراجعة.`,
    changes_requested: `${offering.name} تحتاج إلى تعديلات. عدّل الخدمة ثم أعد إرسالها للمراجعة.`,
    hidden: `${offering.name} تم إخفاؤها من الإدارة.`,
    pending: `${offering.name} تم تحديثها وتنتظر مراجعة جديدة.`,
  };
  const details = note ? `\n${note}` : '';

  await createManyNotifications(
    [...recipients.values()].map((item) => ({
      ...item,
      title: titleMap[normalizedStatus] || 'تحديث على الخدمة',
      body: `${bodyMap[normalizedStatus] || `${offering.name} تم تحديثها.`}${details}`,
      payload: {
        ...item.payload,
        moderationStatus: normalizedStatus,
        moderationNote: note || offering.moderationNote || null,
        requiresAction: normalizedStatus !== 'approved',
      },
    }))
  ).catch(() => {});
}

async function ensureProviderExists(userId) {
  const provider = await repo.getProviderProfileByUserId(userId);
  if (!provider) {
    throw new AppError('SERVICE_PROVIDER_PROFILE_NOT_FOUND', { status: 404 });
  }
  return provider;
}

function assertRoleIsServiceProvider(userRole) {
  if (String(userRole || '').toLowerCase() !== 'service_provider') {
    throw new AppError('FORBIDDEN_SERVICE_PROVIDER_ONLY', { status: 403 });
  }
}

async function resolveProviderAccess({ userId, userRole }) {
  assertRoleIsServiceProvider(userRole);
  const actorUserId = toActorUserId({ userId });
  const ownerProvider = await repo.findOwnerProviderByUserId(actorUserId);
  if (ownerProvider) {
    const ownerPermissions = buildWorkspacePermissionPayload(
      SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS,
      'service_provider'
    );
    return {
      provider: ownerProvider,
      isOwner: true,
      employeeProfile: null,
      permissions: ownerPermissions.permissions,
      permissionMap: ownerPermissions.permissionMap,
    };
  }

  const employeeAccess = await repo.findProviderByEmployeeUserId(actorUserId);
  if (!employeeAccess?.provider) {
    throw new AppError('SERVICE_PROVIDER_PROFILE_NOT_FOUND', { status: 404 });
  }

  return {
    provider: employeeAccess.provider,
    isOwner: false,
    employeeProfile: employeeAccess.employeeProfile || null,
    permissions: employeeAccess.employeeProfile?.permissions || [],
    permissionMap: buildWorkspacePermissionPayload(
      employeeAccess.employeeProfile?.permissions || [],
      'service_provider'
    ).permissionMap,
  };
}

function assertProviderApproved(provider) {
  const status = normalizeProviderApplicationState(
    provider?.providerApprovalStatus
  );
  if (status !== 'approved') {
    throw new AppError('SERVICE_PROVIDER_APPLICATION_UNDER_REVIEW', {
      status: 403,
      details: { status },
    });
  }
}

async function ensureProviderPermission(actor, permission) {
  const access = await resolveProviderAccess(actor);
  assertProviderApproved(access.provider);
  if (access.isOwner) return access;
  if (!hasPermission(access.employeeProfile?.permissions || [], permission)) {
    throw new AppError('FORBIDDEN_SERVICE_PROVIDER_PERMISSION', { status: 403 });
  }
  return access;
}

export async function registerServiceProvider(dto, assets = {}, _deviceContext = {}) {
  const phone = normalizePhone(dto.phone);
  const pin = normalizePin(dto.pin);

  if (!phone) {
    throw new AppError('VALIDATION_ERROR', {
      status: 400,
      details: { fields: ['phone'] },
    });
  }
  if (!pin || !/^\d{4,8}$/.test(pin)) {
    throw new AppError('VALIDATION_ERROR', {
      status: 400,
      details: { fields: ['pin'] },
    });
  }

  const fullName = String(dto.fullName || dto.businessName || '').trim();
  if (!fullName) {
    throw new AppError('VALIDATION_ERROR', {
      status: 400,
      details: { fields: ['fullName'] },
    });
  }

  const existingUser = await findUserByPhone(phone);
  let user = existingUser || null;
  if (existingUser) {
    if (String(existingUser.role || '').toLowerCase() !== 'service_provider') {
      throw new AppError('PHONE_EXISTS', { status: 409 });
    }
    const pinVerification = await verifyPinDetailed(pin, existingUser.pin_hash || '');
    if (!pinVerification.ok) {
      throw new AppError('INVALID_CREDENTIALS', { status: 401 });
    }
  } else {
    const pinHash = await hashPin(pin);
    user = await runWithGeneratedAppUserUsername({
      fullName,
      phone,
      async execute(username) {
        return createUser({
          fullName,
          username,
          phone,
          pinHash,
          block: 'A1',
          buildingNumber: 'A101',
          apartment: '101',
          imageUrl: assets.logoUrl || null,
          role: 'service_provider',
          analyticsConsentGranted: true,
          analyticsConsentVersion: 'analytics_v1',
          analyticsConsentGrantedAt: new Date().toISOString(),
        });
      },
    });
  }

  let provider = await repo.getProviderProfileByUserId(user.id);
  const reusedExistingApplication = !!provider;
  if (!provider) {
    provider = await repo.createProviderProfile({
      userId: user.id,
      dto: {
        ...dto,
        phone,
        businessName: dto.businessName || fullName,
      },
      assets,
      moderation: {
        approvalStatus: 'pending',
        approvalNote: 'Submitted for free provider review',
      },
    });
  }

  if (!reusedExistingApplication) {
    await notifyBackoffice((adminUserId) => ({
      userId: adminUserId,
      type: 'services.provider.application.submitted',
      title: 'طلب تسجيل مقدم خدمة جديد',
      body: `${provider.businessName || fullName} أرسل طلب تسجيل مجاني للمراجعة.`,
      payload: {
        target: 'admin_services_pending_providers',
        targetModule: 'admin',
        providerId: provider.id,
        requiresAction: true,
      },
    }));
  }

  return mapFreeProviderApplicationProgress({
    provider,
    submitted: !reusedExistingApplication,
    reusedExistingApplication,
  });
}

export async function getProviderSubscriptionStatus({ phone, pin }) {
  const normalizedPhone = normalizePhone(phone);
  const normalizedPin = normalizePin(pin);
  if (!normalizedPhone || !normalizedPin) {
    throw new AppError('VALIDATION_ERROR', {
      status: 400,
      details: { fields: ['phone', 'pin'] },
    });
  }

  const user = await findUserByPhone(normalizedPhone);
  if (user) {
    if (String(user.role || '').toLowerCase() !== 'service_provider') {
      throw new AppError('SERVICE_PROVIDER_APPLICATION_NOT_FOUND', {
        status: 404,
      });
    }
    const pinVerification = await verifyPinDetailed(
      normalizedPin,
      user.pin_hash || ''
    );
    if (!pinVerification.ok) {
      throw new AppError('INVALID_CREDENTIALS', { status: 401 });
    }
    const provider = await repo.getProviderProfileByUserId(user.id);
    if (!provider) {
      throw new AppError('SERVICE_PROVIDER_APPLICATION_NOT_FOUND', {
        status: 404,
      });
    }
    return mapFreeProviderApplicationProgress({ provider });
  }

  const authRow = await repo.getProviderSubscriptionRequestAuthByPhone(
    normalizedPhone
  );
  if (!authRow) {
    throw new AppError('SERVICE_PROVIDER_APPLICATION_NOT_FOUND', {
      status: 404,
    });
  }

  const pinVerification = await verifyPinDetailed(
    normalizedPin,
    authRow.pin_hash || ''
  );
  if (!pinVerification.ok) {
    throw new AppError('INVALID_CREDENTIALS', { status: 401 });
  }
  if (pinVerification.needsUpgrade) {
    await repo.updateProviderSubscriptionRequestPinHash(
      authRow.id,
      await hashPin(normalizedPin)
    ).catch(() => null);
  }

  const request = await repo.getProviderSubscriptionRequestById(authRow.id);
  if (!request) {
    throw new AppError('SERVICE_PROVIDER_SUBSCRIPTION_REQUEST_NOT_FOUND', {
      status: 404,
    });
  }
  return mapFreeProviderApplicationProgress({ legacyRequest: request });
}

export async function respondProviderSubscriptionOffer({
  requestId,
  dto,
}) {
  throw new AppError('SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED', {
    status: 410,
  });
}

export async function listProviderSubscriptionRequestsForAdmin({ query }) {
  throw new AppError('SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED', {
    status: 410,
  });
}

export async function adminSendProviderSubscriptionOffer({
  requestId,
  dto,
  adminUserId,
}) {
  throw new AppError('SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED', {
    status: 410,
  });
}

export async function adminRejectProviderSubscriptionRequest({
  requestId,
  dto,
  adminUserId,
}) {
  throw new AppError('SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED', {
    status: 410,
  });
}

export async function adminConfirmProviderSubscriptionCashPayment({
  requestId,
  dto,
  adminUserId,
}) {
  throw new AppError('SERVICE_PROVIDER_EXTERNAL_PAYMENT_DISABLED', {
    status: 410,
  });
}

export async function listPublicCategories({ q = '' } = {}) {
  return repo.listPublicCategories({ q });
}

export async function createPublicCategory({ userId, dto }) {
  const actorUserId = Number(userId);
  if (!Number.isInteger(actorUserId) || actorUserId <= 0) {
    throw new AppError('UNAUTHORIZED', { status: 401 });
  }
  const parentCategoryId = dto.parentCategoryId == null ? null : Number(dto.parentCategoryId);
  if (parentCategoryId != null) {
    const parent = await repo.getPublicCategoryById(parentCategoryId);
    if (!parent || parent.level !== 1) {
      throw new AppError('SERVICE_CATEGORY_PARENT_NOT_FOUND', { status: 404 });
    }
  }
  return repo.createPublicCategory({
    userId: actorUserId,
    name: dto.name,
    parentCategoryId,
  });
}

export async function searchPublicOfferings(query, viewerUserId = null) {
  const list = await repo.searchPublicOfferings(query, { viewerUserId });
  return list.map(attachPricingDisplay);
}

export async function getPublicProvider(providerId, viewerUserId = null) {
  const provider = await repo.getPublicProviderById(providerId);
  if (!provider) return null;
  if (viewerUserId) {
    await repo.recordRecentView({
      userId: viewerUserId,
      providerId: provider.id,
      offeringId: null,
    }).catch(() => {});
  }
  return provider;
}

export async function getPublicOffering(offeringId, viewerUserId = null) {
  const offering = await repo.getPublicOfferingById(offeringId);
  if (!offering) return null;
  if (viewerUserId) {
    await repo.recordRecentView({
      userId: viewerUserId,
      providerId: offering.providerId,
      offeringId: offering.id,
    }).catch(() => {});
  }
  return attachPricingDisplay(offering);
}

export async function getProviderWorkspace({ userId, userRole }) {
  const access = await resolveProviderAccess({ userId, userRole });
  assertProviderApproved(access.provider);
  const workspace = await repo.listProviderWorkspace(userId);
  if (!workspace) {
    throw new AppError('SERVICE_PROVIDER_PROFILE_NOT_FOUND', { status: 404 });
  }
  const canViewRequests = access.isOwner || hasPermission(access.permissions, 'view_service_requests');
  const canManageEmployees = access.isOwner || hasPermission(access.permissions, 'manage_employees');
  const canViewAuditLog = access.isOwner || hasPermission(access.permissions, 'view_audit_log');
  const employeePermissions = access.isOwner
    ? SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS
    : access.permissions;
  const permissionPayload = buildWorkspacePermissionPayload(
    employeePermissions,
    'service_provider'
  );

  const employees = canManageEmployees
    ? await repo.listProviderEmployees({
        providerId: workspace.provider.id,
        limit: 120,
      })
    : [];
  const activityLogs = canViewAuditLog
    ? await repo.listProviderEmployeeActivityLogs({
        providerId: workspace.provider.id,
        limit: 120,
      })
    : [];

  return {
    ...workspace,
    requestCounts: canViewRequests ? workspace.requestCounts : {},
    availablePermissions: SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS,
    access: {
      isOwner: access.isOwner,
      permissions: permissionPayload.permissions,
      permissionMap: permissionPayload.permissionMap,
      employeeProfile: access.employeeProfile || null,
    },
    employees: employees.map(mapProviderEmployeeRow),
    activityLogs: activityLogs.map(mapProviderEmployeeActivityLog),
  };
}

export async function getProviderProfile({ userId, userRole }) {
  await resolveProviderAccess({ userId, userRole });
  return ensureProviderExists(userId);
}

export async function updateProviderProfile({ userId, userRole, dto, assets = {} }) {
  const access = await ensureProviderPermission(
    { userId, userRole },
    'manage_service_profile'
  );
  const profile = await repo.updateProviderProfile({ userId, dto, assets });
  if (!profile) {
    throw new AppError('SERVICE_PROVIDER_PROFILE_NOT_FOUND', { status: 404 });
  }
  if (!access.provider) {
    throw new AppError('SERVICE_PROVIDER_PROFILE_NOT_FOUND', { status: 404 });
  }
  return profile;
}

export async function createOffering({
  userId,
  userRole,
  dto,
  mediaUrls = [],
}) {
  await ensureProviderPermission({ userId, userRole }, 'create_services');
  const offering = await repo.createOfferingForProvider({
    userId,
    dto,
    mediaUrls,
  });
  if (!offering) {
    throw new AppError('SERVICE_PROVIDER_PROFILE_NOT_FOUND', { status: 404 });
  }
  return offering;
}

export async function updateOffering({
  userId,
  userRole,
  offeringId,
  dto,
  mediaUrls = [],
}) {
  await ensureProviderPermission({ userId, userRole }, 'edit_services');
  const offering = await repo.updateOfferingForProvider({
    userId,
    offeringId,
    dto,
    mediaUrls,
  });
  if (!offering) {
    throw new AppError('SERVICE_OFFERING_NOT_FOUND', { status: 404 });
  }
  return offering;
}

export async function replaceOfferingPricing({
  userId,
  userRole,
  offeringId,
  pricingOptions,
}) {
  await ensureProviderPermission({ userId, userRole }, 'edit_services');
  if (!Array.isArray(pricingOptions) || pricingOptions.length === 0) {
    throw new AppError('VALIDATION_ERROR', {
      status: 400,
      details: { fields: ['pricingOptions'] },
    });
  }
  for (const item of pricingOptions) {
    const model = String(item?.pricingModel || '').trim().toLowerCase();
    if (!SERVICE_PRICING_MODELS.includes(model)) {
      throw new AppError('VALIDATION_ERROR', {
        status: 400,
        details: { fields: ['pricingModel'] },
      });
    }
  }
  const offering = await repo.replacePricingForOffering({
    userId,
    offeringId,
    pricingOptions,
  });
  if (!offering) {
    throw new AppError('SERVICE_OFFERING_NOT_FOUND', { status: 404 });
  }
  return offering;
}

export async function createPromotion({ userId, userRole, dto }) {
  await ensureProviderPermission({ userId, userRole }, 'manage_offers');
  const promotion = await repo.createPromotionForProvider({ userId, dto });
  if (!promotion) {
    throw new AppError('SERVICE_PROVIDER_PROFILE_NOT_FOUND', { status: 404 });
  }
  return promotion;
}

export async function createPortfolioItem({
  userId,
  userRole,
  dto,
  mediaUrl,
}) {
  await ensureProviderPermission({ userId, userRole }, 'edit_services');
  if (!mediaUrl) {
    throw new AppError('VALIDATION_ERROR', {
      status: 400,
      details: { fields: ['mediaUrl'] },
    });
  }
  const item = await repo.createPortfolioItemForProvider({
    userId,
    dto,
    mediaUrl,
  });
  if (!item) {
    throw new AppError('SERVICE_PROVIDER_PROFILE_NOT_FOUND', { status: 404 });
  }
  return item;
}

export async function deletePortfolioItem({ userId, userRole, portfolioId }) {
  await ensureProviderPermission({ userId, userRole }, 'edit_services');
  const ok = await repo.deletePortfolioItemForProvider({ userId, portfolioId });
  if (!ok) {
    throw new AppError('SERVICE_PORTFOLIO_ITEM_NOT_FOUND', { status: 404 });
  }
  return { deleted: true };
}

export async function createCategorySuggestion({ userId, userRole, dto }) {
  assertRoleIsServiceProvider(userRole);
  return repo.createCategorySuggestion({ userId, dto });
}

export async function listMyCategorySuggestions({ userId, userRole, query }) {
  assertRoleIsServiceProvider(userRole);
  return repo.listMyCategorySuggestions(userId, query);
}

export async function listProviderRequests({ userId, userRole, query }) {
  await ensureProviderPermission({ userId, userRole }, 'view_service_requests');
  return repo.listProviderRequestsByUser({ userId, query });
}

export async function createQuote({ userId, userRole, requestId, dto }) {
  await ensureProviderPermission({ userId, userRole }, 'view_service_requests');
  const quote = await repo.createQuoteForRequest({
    userId,
    requestId,
    dto,
  });
  if (!quote) {
    throw new AppError('SERVICE_REQUEST_NOT_FOUND', { status: 404 });
  }
  const request = await repo.getServiceRequestForUser({ userId, requestId });
  if (request?.customerUserId) {
    await createNotification({
      userId: Number(request.customerUserId),
      type: 'services.request.quote_received',
      title: 'ØªÙ… Ø¥Ø±Ø³Ø§Ù„ Ø¹Ø±Ø¶ Ø³Ø¹Ø± Ù„Ø·Ù„Ø¨Ùƒ',
      body: 'Ø±Ø§Ø¬Ø¹ Ø§Ù„Ø¹Ø±Ø¶ Ø§Ù„Ø¬Ø¯ÙŠØ¯ ÙˆÙ‚Ø±Ø± Ø§Ù„Ù‚Ø¨ÙˆÙ„ Ø£Ùˆ Ø§Ù„Ø±ÙØ¶.',
      payload: {
        target: 'service_request_details',
        targetModule: 'customer',
        requestId: Number(requestId),
        quoteId: quote.id,
        requiresAction: true,
      },
    }).catch(() => {});
  }
  return quote;
}

export async function updateRequestStatusByProvider({
  userId,
  userRole,
  requestId,
  dto,
}) {
  const normalizedStatus = String(dto.status || '').trim().toLowerCase();
  if (normalizedStatus === 'rejected') {
    await ensureProviderPermission({ userId, userRole }, 'reject_service_requests');
  } else if (
    ['accepted', 'scheduled', 'in_progress', 'completed'].includes(normalizedStatus)
  ) {
    await ensureProviderPermission({ userId, userRole }, 'accept_service_requests');
  } else {
    await ensureProviderPermission({ userId, userRole }, 'view_service_requests');
  }
  const updated = await repo.updateRequestStatusByProviderUser({
    userId,
    requestId,
    status: dto.status,
    note: dto.note || null,
    scheduledStartAt: dto.scheduledStartAt || null,
    scheduledEndAt: dto.scheduledEndAt || null,
    expectedVersion: dto.expectedVersion ?? null,
    idempotencyKey: dto.idempotencyKey ?? null,
  });
  if (!updated) {
    throw new AppError('SERVICE_REQUEST_NOT_FOUND', { status: 404 });
  }
  if (updated.customerUserId) {
    const notificationStatus = String(updated.status || dto.status || '')
      .trim()
      .toLowerCase();
    await createNotification({
      userId: Number(updated.customerUserId),
      type: `services.request.status.${notificationStatus}`,
      title: 'ØªÙ… ØªØ­Ø¯ÙŠØ« Ø­Ø§Ù„Ø© Ø·Ù„Ø¨ Ø§Ù„Ø®Ø¯Ù…Ø©',
      body: `Ø­Ø§Ù„Ø© Ø·Ù„Ø¨Ùƒ Ø§Ù„Ø¢Ù†: ${notificationStatus}`,
      payload: {
        target: 'service_request_details',
        targetModule: 'customer',
        requestId: updated.id,
        requiresAction: false,
      },
    }).catch(() => {});
  }
  return updated;
}

export async function listProviderEmployees(
  { userId, userRole },
  { search = '', limit = 120 } = {}
) {
  const access = await ensureProviderPermission(
    { userId, userRole },
    'manage_employees'
  );
  const rows = await repo.listProviderEmployees({
    providerId: access.provider.id,
    search,
    limit,
  });
  return {
    provider: access.provider,
    items: rows.map(mapProviderEmployeeRow),
    availablePermissions: SERVICE_PROVIDER_EMPLOYEE_PERMISSION_KEYS,
    access: {
      isOwner: access.isOwner,
      permissions: access.permissions,
      permissionMap: access.permissionMap,
      employeeProfile: access.employeeProfile || null,
    },
  };
}

export async function upsertProviderEmployee({ userId, userRole }, dto) {
  const access = await ensureProviderPermission(
    { userId, userRole },
    'manage_employees'
  );
  const actorUserId = toActorUserId({ userId });
  const employeeUserId = Number(dto.employeeUserId);
  if (!Number.isInteger(employeeUserId) || employeeUserId <= 0) {
    throw new AppError('EMPLOYEE_REQUIRED', { status: 400 });
  }

  const permissions = buildWorkspacePermissionPayload(
    dto.permissions,
    'service_provider'
  ).permissions;
  const previousProfile = await repo.findAnyEmployeeProfileForProvider({
    providerId: access.provider.id,
    employeeUserId,
  });
  const archivedAt =
    dto.archivedAt || (dto.isActive === false ? new Date().toISOString() : null);
  const out = await repo.upsertProviderEmployeeProfile({
    providerId: access.provider.id,
    employeeUserId,
    roleTag: String(dto.roleTag || 'staff').trim().slice(0, 80) || 'staff',
    displayName: dto.displayName || null,
    contactEmail: dto.contactEmail || null,
    permissions,
    isActive: dto.isActive !== false,
    archivedAt,
    notes: dto.notes || null,
    invitedByUserId: dto.invitedByUserId == null ? actorUserId : Number(dto.invitedByUserId),
    updatedByUserId: actorUserId,
  });

  await repo.insertProviderEmployeeActivityLog({
    workspaceKind: 'service_provider',
    workspaceId: access.provider.id,
    employeeProfileId: Number(out.id),
    employeeUserId,
    actorUserId,
    actorRole: normalizeRole(userRole),
    actionKey: 'service_provider.employee.updated',
    reason: dto.reason || null,
    oldValue: previousProfile
      ? {
          displayName: previousProfile.display_name || null,
          contactEmail: previousProfile.contact_email || null,
          permissions: Array.isArray(previousProfile.permissions_json)
            ? previousProfile.permissions_json
            : [],
          isActive: previousProfile.is_active === true,
          archivedAt: previousProfile.archived_at || null,
        }
      : {},
    newValue: {
      displayName: out.display_name || null,
      contactEmail: out.contact_email || null,
      permissions,
      isActive: out.is_active === true,
      archivedAt: out.archived_at || null,
    },
    note: dto.notes || null,
  });

  return {
    provider: access.provider,
    profile: mapProviderEmployeeProfileRow(out),
  };
}

export async function inviteProviderEmployee({ userId, userRole }, dto) {
  const access = await ensureProviderPermission(
    { userId, userRole },
    'manage_employees'
  );
  const actorUserId = toActorUserId({ userId });
  const phone = normalizePhone(dto.phone);
  const pin = normalizePin(dto.pin);
  const fullName = String(dto.fullName || '').trim();
  const displayName = String(dto.displayName || fullName || '').trim();
  const contactEmail = String(dto.contactEmail || '').trim() || null;

  if (!fullName) {
    throw new AppError('FULL_NAME_REQUIRED', { status: 400 });
  }
  if (!/^\d{8,20}$/.test(phone)) {
    throw new AppError('PHONE_INVALID', { status: 400 });
  }
  if (!/^\d{4,8}$/.test(pin)) {
    throw new AppError('PIN_INVALID', { status: 400 });
  }

  const existing = await findUserByPhone(phone);
  if (existing) {
    throw new AppError('PHONE_EXISTS', { status: 409 });
  }

  const pinHash = await hashPin(pin);
  const created = await runWithGeneratedAppUserUsername({
    fullName,
    phone,
    execute: (username) =>
      createUser({
        fullName,
        username,
        phone,
        pinHash,
        block: 'A',
        buildingNumber: 'A101',
        apartment: '101',
        imageUrl: null,
        role: 'service_provider',
        analyticsConsentGranted: true,
        analyticsConsentVersion: 'service_provider_employee_v1',
        analyticsConsentGrantedAt: new Date().toISOString(),
        chatQualityReviewConsent: true,
      }),
  });

  const permissions = buildWorkspacePermissionPayload(
    dto.permissions,
    'service_provider'
  ).permissions;
  const out = await repo.upsertProviderEmployeeProfile({
    providerId: access.provider.id,
    employeeUserId: Number(created.id),
    roleTag: String(dto.roleTag || 'staff').trim().slice(0, 80) || 'staff',
    displayName,
    contactEmail,
    permissions,
    isActive: dto.isActive !== false,
    archivedAt: dto.archivedAt || null,
    notes: dto.notes || null,
    invitedByUserId: actorUserId,
    updatedByUserId: actorUserId,
  });

  await repo.insertProviderEmployeeActivityLog({
    workspaceKind: 'service_provider',
    workspaceId: access.provider.id,
    employeeProfileId: Number(out.id),
    employeeUserId: Number(created.id),
    actorUserId,
    actorRole: normalizeRole(userRole),
    actionKey: 'service_provider.employee.invited',
    reason: dto.reason || null,
    oldValue: {},
    newValue: {
      displayName: out.display_name || displayName,
      contactEmail: out.contact_email || contactEmail,
      permissions,
      isActive: out.is_active === true,
    },
    note: dto.notes || null,
  });

  return {
    provider: access.provider,
    user: {
      id: Number(created.id),
      fullName: created.full_name,
      phone: created.phone,
      role: created.role,
    },
    profile: mapProviderEmployeeProfileRow(out),
  };
}

export async function listProviderEmployeeActivityLogs(
  { userId, userRole },
  { employeeUserId = null, limit = 120 } = {}
) {
  const access = await ensureProviderPermission(
    { userId, userRole },
    'view_audit_log'
  );
  const rows = await repo.listProviderEmployeeActivityLogs({
    providerId: access.provider.id,
    employeeUserId: employeeUserId == null ? null : Number(employeeUserId),
    limit,
  });
  return {
    provider: access.provider,
    items: rows.map(mapProviderEmployeeActivityLog),
  };
}

export async function createServiceRequest({
  userId,
  dto,
  attachments = [],
}) {
  const created = await repo.createServiceRequestByCustomer({
    customerUserId: userId,
    dto,
    attachments,
  });
  if (!created) {
    throw new AppError('SERVICE_OFFERING_NOT_FOUND', { status: 404 });
  }

  const provider = await repo.getPublicProviderById(created.providerId).catch(() => null);
  if (provider?.userId) {
    await createNotification({
      userId: Number(provider.userId),
      type: 'services.request.created',
      title: 'Ø·Ù„Ø¨ Ø®Ø¯Ù…Ø© Ø¬Ø¯ÙŠØ¯',
      body: `Ø·Ù„Ø¨ Ø¬Ø¯ÙŠØ¯ Ù…Ù† Ø§Ù„Ø¹Ù…ÙŠÙ„ Ø¨Ø®ØµÙˆØµ ${created.offeringName || 'Ø®Ø¯Ù…Ø©'}.`,
      payload: {
        target: 'service_request_details',
        targetModule: 'customer',
        requestId: created.id,
        requiresAction: true,
      },
    }).catch(() => {});
  }

  const providerEmployees = await repo
    .listActiveProviderNotificationRecipients({
      providerId: created.providerId,
      requiredPermissions: [
        'view_service_requests',
        'accept_service_requests',
        'reject_service_requests',
      ],
    })
    .catch(() => []);
  if (providerEmployees.length > 0) {
    await createManyNotifications(
      providerEmployees.map((employee) => ({
        userId: Number(employee.userId),
        type: 'services.request.created',
        title: 'Ø·Ù„Ø¨ Ø®Ø¯Ù…Ø© Ø¬Ø¯ÙŠØ¯',
        body: `Ø·Ù„Ø¨ Ø¬Ø¯ÙŠØ¯ Ù…Ù† Ø§Ù„Ø¹Ù…ÙŠÙ„ Ø¨Ø®ØµÙˆØµ ${created.offeringName || 'Ø®Ø¯Ù…Ø©'}.`,
        payload: {
          target: 'service_request_details',
          targetModule: 'customer',
          requestId: created.id,
          requiresAction: true,
        },
      }))
    ).catch(() => {});
  }

  return created;
}

export async function previewServiceBooking({ userId, dto }) {
  const out = await repo.previewServiceBookingByCustomer({
    customerUserId: userId,
    dto,
  });
  if (!out) {
    throw new AppError('SERVICE_OFFERING_NOT_FOUND', { status: 404 });
  }
  return out;
}

export async function listMyRequests({ userId, query }) {
  return repo.listCustomerRequests({ userId, query });
}

export async function getMyRequest({ userId, requestId }) {
  const item = await repo.getServiceRequestForUser({ userId, requestId });
  if (!item) {
    throw new AppError('SERVICE_REQUEST_NOT_FOUND', { status: 404 });
  }
  return item;
}

export async function updateRequestStatusByCustomer({
  userId,
  requestId,
  dto,
}) {
  const updated = await repo.updateRequestStatusByCustomer({
    userId,
    requestId,
    status: dto.status,
    note: dto.note || null,
    expectedVersion: dto.expectedVersion ?? null,
    idempotencyKey: dto.idempotencyKey ?? null,
  });
  if (!updated) {
    throw new AppError('SERVICE_REQUEST_NOT_FOUND', { status: 404 });
  }
  return updated;
}

export async function respondToQuote({
  userId,
  requestId,
  quoteId,
  dto,
}) {
  const updated = await repo.respondToQuoteByCustomer({
    userId,
    requestId,
    quoteId,
    action: dto.action,
    note: dto.note || null,
  });
  if (!updated) {
    throw new AppError('SERVICE_REQUEST_NOT_FOUND', { status: 404 });
  }
  return updated;
}

export async function createReview({ userId, dto }) {
  const out = await repo.createReviewByCustomer({ userId, dto });
  if (!out) {
    throw new AppError('SERVICE_REQUEST_NOT_FOUND', { status: 404 });
  }
  if (out.error) {
    throw new AppError(out.error, { status: 400 });
  }
  return out;
}

export async function listProviderReviews(providerId, query) {
  return repo.listProviderReviews(providerId, query);
}

export async function listOfferingReviews(offeringId, query) {
  return repo.listOfferingReviews(offeringId, query);
}

export async function saveProvider({ userId, providerId }) {
  await repo.saveProvider(userId, providerId);
  return { saved: true };
}

export async function unsaveProvider({ userId, providerId }) {
  await repo.unsaveProvider(userId, providerId);
  return { saved: false };
}

export async function saveOffering({ userId, offeringId }) {
  await repo.saveOffering(userId, offeringId);
  return { saved: true };
}

export async function unsaveOffering({ userId, offeringId }) {
  await repo.unsaveOffering(userId, offeringId);
  return { saved: false };
}

export async function listSavedProviders({ userId, query }) {
  return repo.listSavedProviders(userId, query);
}

export async function listSavedOfferings({ userId, query }) {
  const list = await repo.listSavedOfferings(userId, query);
  return list.map(attachPricingDisplay);
}

export async function listRecentViews({ userId, query }) {
  return repo.listRecentViews(userId, query);
}

export async function listPendingProviders({ query }) {
  return repo.listPendingProvidersForAdmin({
    status: query.providerStatus || 'pending',
    limit: query.limit,
    offset: query.offset,
  });
}

export async function adminUpdateProviderStatus({
  providerId,
  dto,
  adminUserId,
}) {
  const provider = await repo.adminUpdateProviderStatus({
    providerId,
    status: dto.status,
    note: dto.note || null,
    adminUserId,
  });
  if (!provider) {
    throw new AppError('SERVICE_PROVIDER_PROFILE_NOT_FOUND', { status: 404 });
  }
  if (provider.userId) {
    await createNotification({
      userId: Number(provider.userId),
      type: `services.provider.status.${dto.status}`,
      title: 'ØªØ­Ø¯ÙŠØ« Ø­Ø§Ù„Ø© Ù…Ø²ÙˆØ¯ Ø§Ù„Ø®Ø¯Ù…Ø©',
      body: `ØªÙ… ØªØ­Ø¯ÙŠØ« Ø­Ø§Ù„Ø© Ø­Ø³Ø§Ø¨Ùƒ Ø¥Ù„Ù‰: ${dto.status}`,
      payload: {
        target: 'services_provider_workspace',
        targetModule: 'customer',
        providerId: provider.id,
        requiresAction: false,
      },
    }).catch(() => {});
  }
  return provider;
}

export async function listOfferingsForAdmin({ query }) {
  return repo.listOfferingsForAdmin({
    status: query.offeringStatus || 'pending',
    limit: query.limit,
    offset: query.offset,
  });
}

export async function adminUpdateOfferingStatus({
  offeringId,
  dto,
  adminUserId,
}) {
  const offering = await repo.adminUpdateOfferingStatus({
    offeringId,
    status: dto.status,
    note: dto.note || null,
    adminUserId,
  });
  if (!offering) {
    throw new AppError('SERVICE_OFFERING_NOT_FOUND', { status: 404 });
  }
  await notifyOfferingModerationToProvider({
    offering,
    status: dto.status,
    note: dto.note || null,
  });
  return offering;
}

export async function listCategorySuggestionsForAdmin({ query }) {
  return repo.listCategorySuggestionsForAdmin({
    status: query.categorySuggestionStatus || 'pending',
    limit: query.limit || 60,
    offset: query.offset || 0,
  });
}

export async function adminReviewCategorySuggestion({
  suggestionId,
  dto,
  adminUserId,
}) {
  const suggestion = await repo.adminReviewCategorySuggestion({
    suggestionId,
    action: dto.action,
    reviewNote: dto.reviewNote || null,
    mergeTargetCategoryId: dto.mergeTargetCategoryId || null,
    adminUserId,
  });
  if (!suggestion) {
    throw new AppError('SERVICE_CATEGORY_SUGGESTION_NOT_FOUND', { status: 404 });
  }
  return suggestion;
}

export async function listServiceReportsForAdmin({ query }) {
  return repo.listServiceReportsForAdmin({
    status: query.status || 'pending',
    limit: query.limit || 60,
    offset: query.offset || 0,
  });
}

export async function adminReviewReport({ reportId, dto, adminUserId }) {
  const reviewed = await repo.adminReviewReport({
    reportId,
    status: dto.status,
    reviewNote: dto.reviewNote || null,
    adminUserId,
  });
  if (!reviewed) {
    throw new AppError('SERVICE_REPORT_NOT_FOUND', { status: 404 });
  }
  return reviewed;
}

export async function listRequestsForAdmin({ query }) {
  return repo.listServiceRequestsForAdmin({
    status: query.requestStatus || null,
    limit: query.limit || 60,
    offset: query.offset || 0,
  });
}

export async function getAdminDashboardStats() {
  return repo.getServicesAdminDashboardStats();
}

export async function listModuleSettings() {
  return repo.listServiceModuleSettings();
}

export async function upsertModuleSetting({ key, value, adminUserId }) {
  return repo.upsertServiceModuleSetting({
    key,
    value,
    adminUserId,
  });
}

