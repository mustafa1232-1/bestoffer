import { pool, q } from '../../config/db.js';
import { AppError } from '../../shared/utils/errors.js';
import { hasPermission } from '../../shared/workspaces/employee-permissions.js';
import {
  assertValidServiceBookingTransition,
  buildServiceBookingPreview,
  normalizeServiceBookingState,
} from './services.booking.core.js';
import { normalizeServicePromotionType } from './services.booking.constants.js';

function toInt(value) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;
  return parsed;
}

function toNum(value) {
  if (value === undefined || value === null || value === '') return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  return parsed;
}

function toIsoOrNull(value) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

function clampLimit(value, fallback = 100) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return fallback;
  return Math.min(200, parsed);
}

function asObj(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  return {};
}

function safeJson(value) {
  if (!value || typeof value !== 'object') return {};
  if (Array.isArray(value)) return [...value];
  return { ...value };
}

const SERVICE_BOOKING_SLOT_ACTIVE_STATUSES = [
  'pending',
  'awaiting_provider',
  'accepted',
  'scheduled',
  'in_progress',
  'PENDING_PROVIDER_CONFIRMATION',
  'CONFIRMED',
  'IN_PROGRESS',
  'PROVIDER_COMPLETED',
];

let ensureServiceBookingSchemaPromise = null;

async function ensureServiceBookingSchema() {
  if (ensureServiceBookingSchemaPromise) return ensureServiceBookingSchemaPromise;

  ensureServiceBookingSchemaPromise = (async () => {
    const client = await pool.connect();
    try {
      await client.query(`SELECT pg_advisory_lock($1)`, [719_244_382]);

      await client.query(`
        ALTER TABLE service_requests
        ADD COLUMN IF NOT EXISTS booking_flow_kind VARCHAR(12);
      `);

      await client.query(`
        ALTER TABLE service_requests
        ALTER COLUMN booking_flow_kind SET DEFAULT 'LEGACY';
      `);

      await client.query(`
        CREATE OR REPLACE FUNCTION service_requests_booking_flow_kind_immutable()
        RETURNS TRIGGER AS $$
        BEGIN
          IF TG_OP = 'INSERT' THEN
            NEW.booking_flow_kind = COALESCE(NULLIF(BTRIM(COALESCE(NEW.booking_flow_kind, '')), ''), 'LEGACY');
            IF NEW.booking_flow_kind NOT IN ('LEGACY', 'V2') THEN
              RAISE EXCEPTION 'booking_flow_kind must be LEGACY or V2';
            END IF;
            RETURN NEW;
          END IF;

          IF TG_OP = 'UPDATE' AND NEW.booking_flow_kind IS DISTINCT FROM OLD.booking_flow_kind THEN
            RAISE EXCEPTION 'booking_flow_kind is immutable once set';
          END IF;

          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      `);

      await client.query(`
        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1
            FROM pg_trigger
            WHERE tgname = 'trg_service_requests_booking_flow_kind_immutable'
              AND tgrelid = 'service_requests'::regclass
              AND NOT tgisinternal
          ) THEN
            CREATE TRIGGER trg_service_requests_booking_flow_kind_immutable
            BEFORE INSERT OR UPDATE OF booking_flow_kind ON service_requests
            FOR EACH ROW
            EXECUTE FUNCTION service_requests_booking_flow_kind_immutable();
          END IF;
        END
        $$;
      `);
    } finally {
      await client.query(`SELECT pg_advisory_unlock($1)`, [719_244_382]).catch(() => {});
      client.release();
    }
  })();

  return ensureServiceBookingSchemaPromise;
}

function mapCategory(row) {
  return {
    id: Number(row.id),
    parentId: row.parent_id == null ? null : Number(row.parent_id),
    level: Number(row.level),
    name: row.name,
    sortOrder: Number(row.sort_order || 0),
    isActive: row.is_active === true,
    isPublic: row.is_public === true,
  };
}

function normalizeCategorySearch(value) {
  return String(value || '')
    .trim()
    .toLowerCase();
}

function buildCategoryTree(rows) {
  const roots = [];
  const byId = new Map();

  for (const row of rows) {
    const category = mapCategory(row);
    if (category.level !== 1) continue;
    const item = { ...category, children: [] };
    roots.push(item);
    byId.set(item.id, item);
  }

  for (const row of rows) {
    const category = mapCategory(row);
    if (category.level !== 2 || category.parentId == null) continue;
    const parent = byId.get(category.parentId);
    if (!parent) continue;
    parent.children.push(category);
  }

  roots.sort((a, b) =>
    a.sortOrder === b.sortOrder
      ? a.name.localeCompare(b.name)
      : a.sortOrder - b.sortOrder
  );
  for (const root of roots) {
    root.children.sort((a, b) =>
      a.sortOrder === b.sortOrder
        ? a.name.localeCompare(b.name)
        : a.sortOrder - b.sortOrder
    );
  }

  return roots;
}

function filterCategoryTree(roots, query) {
  const normalized = normalizeCategorySearch(query);
  if (!normalized) return roots;

  return roots
    .map((root) => {
      const rootMatches = normalizeCategorySearch(root.name).includes(normalized);
      const children = rootMatches
        ? root.children
        : root.children.filter((child) =>
            normalizeCategorySearch(child.name).includes(normalized)
          );
      if (!rootMatches && children.length === 0) return null;
      return {
        ...root,
        children,
      };
    })
    .filter(Boolean);
}

function mapProvider(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    userId: Number(row.user_id),
    businessName: row.business_name,
    logoUrl: row.logo_url || null,
    coverImageUrl: row.cover_image_url || null,
    mainCategoryId: row.main_category_id == null ? null : Number(row.main_category_id),
    mainCategoryName: row.main_category_name || null,
    bio: row.bio || null,
    phone: row.phone || null,
    whatsappPhone: row.whatsapp_phone || null,
    city: row.city || null,
    area: row.area || null,
    addressLine: row.address_line || null,
    servesAtHome: row.serves_at_home === true,
    servesAtShop: row.serves_at_shop === true,
    servesRemote: row.serves_remote === true,
    hasEmergencyService: row.has_emergency_service === true,
    bookingPolicy: row.booking_policy || 'approval_required',
    pricingMode: row.pricing_mode || 'mixed',
    providerApprovalStatus: row.provider_approval_status || 'pending',
    approvalNote: row.approval_note || null,
    yearsExperience: row.years_experience == null ? null : Number(row.years_experience),
    isVerified: row.is_verified === true,
    hasTeam: row.has_team === true,
    teamSize: row.team_size == null ? null : Number(row.team_size),
    acceptsCash: row.accepts_cash === true,
    acceptsElectronic: row.accepts_electronic === true,
    averageResponseMinutes:
      row.average_response_minutes == null ? null : Number(row.average_response_minutes),
    isAvailable247: row.is_available_24_7 === true,
    languages: Array.isArray(row.languages_json) ? row.languages_json : [],
    providerGender: row.provider_gender || null,
    completedOrdersCount: Number(row.completed_orders_count || 0),
    ratingAvg: Number(row.rating_avg || 0),
    ratingCount: Number(row.rating_count || 0),
    isFeatured: row.is_featured === true,
    isActive: row.is_active === true,
    isTemporarilyPaused: row.is_temporarily_paused === true,
    pauseReason: row.pause_reason || null,
    owner: {
      id: row.owner_id == null ? null : Number(row.owner_id),
      fullName: row.owner_full_name || null,
      imageUrl: row.owner_image_url || null,
    },
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function legacyServiceRequestStatus(value, row = null) {
  const normalized = normalizeServiceBookingState(value);
  switch (normalized || String(value || '').trim().toLowerCase()) {
    case 'PENDING_PROVIDER_CONFIRMATION':
      return row?.requires_quote === true ? 'awaiting_provider' : 'pending';
    case 'CONFIRMED':
      return 'accepted';
    case 'IN_PROGRESS':
      return 'in_progress';
    case 'PROVIDER_COMPLETED':
    case 'COMPLETED':
      return 'completed';
    case 'REJECTED_BY_PROVIDER':
      return 'rejected';
    case 'CANCELLED_BY_CUSTOMER':
    case 'CANCELLED_BY_PROVIDER':
    case 'CANCELLED_BY_ADMIN':
      return 'cancelled';
    case 'EXPIRED':
      return 'expired';
    case 'DISPUTED':
      return 'disputed';
    default:
      return value || null;
  }
}

function mapOffering(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    providerId: Number(row.provider_id),
    mainCategoryId: row.main_category_id == null ? null : Number(row.main_category_id),
    mainCategoryName: row.main_category_name || null,
    subcategoryId: row.subcategory_id == null ? null : Number(row.subcategory_id),
    subcategoryName: row.subcategory_name || null,
    name: row.name,
    description: row.description || null,
    executionMode: row.execution_mode || 'both',
    requiresSchedule: row.requires_schedule === true,
    requiresProviderApproval: row.requires_provider_approval === true,
    estimatedDurationMinutes:
      row.estimated_duration_minutes == null
        ? null
        : Number(row.estimated_duration_minutes),
    hasFixedPrice: row.has_fixed_price === true,
    startsFromPrice: row.starts_from_price == null ? null : Number(row.starts_from_price),
    inspectionRequired: row.inspection_required === true,
    customQuoteOnly: row.custom_quote_only === true,
    workersCount: row.workers_count == null ? null : Number(row.workers_count),
    includesText: row.includes_text || null,
    excludesText: row.excludes_text || null,
    materialsText: row.materials_text || null,
    notes: row.notes || null,
    supportsHourlyBooking: row.supports_hourly_booking === true,
    supportsDailyBooking: row.supports_daily_booking === true,
    supportsVisitBooking: row.supports_visit_booking === true,
    supportsFullDayBooking: row.supports_full_day_booking === true,
    moderationStatus: row.moderation_status || 'pending',
    moderationNote: row.moderation_note || null,
    isActive: row.is_active === true,
    isTemporarilyPaused: row.is_temporarily_paused === true,
    pauseReason: row.pause_reason || null,
    completedOrdersCount: Number(row.completed_orders_count || 0),
    ratingAvg: Number(row.rating_avg || 0),
    ratingCount: Number(row.rating_count || 0),
    provider: {
      id: Number(row.provider_id),
      businessName: row.provider_business_name || null,
      city: row.provider_city || null,
      area: row.provider_area || null,
      ratingAvg: row.provider_rating_avg == null ? null : Number(row.provider_rating_avg),
      ratingCount:
        row.provider_rating_count == null ? null : Number(row.provider_rating_count),
      completedOrdersCount:
        row.provider_completed_orders_count == null
          ? null
          : Number(row.provider_completed_orders_count),
      hasEmergencyService: row.provider_has_emergency_service === true,
      isFeatured: row.provider_is_featured === true,
      logoUrl: row.provider_logo_url || null,
      approvalStatus: row.provider_approval_status || null,
      averageResponseMinutes:
        row.provider_average_response_minutes == null
          ? null
          : Number(row.provider_average_response_minutes),
      isTemporarilyPaused: row.provider_is_temporarily_paused === true,
    },
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapPricing(row) {
  return {
    id: Number(row.id),
    offeringId: Number(row.offering_id),
    pricingModel: row.pricing_model,
    pricingUnit: row.pricing_unit,
    label: row.label || null,
    amount: row.amount == null ? null : Number(row.amount),
    minAmount: row.min_amount == null ? null : Number(row.min_amount),
    maxAmount: row.max_amount == null ? null : Number(row.max_amount),
    visitFee: row.visit_fee == null ? null : Number(row.visit_fee),
    currency: row.currency || 'IQD',
    minQuantity: row.min_quantity == null ? null : Number(row.min_quantity),
    maxQuantity: row.max_quantity == null ? null : Number(row.max_quantity),
    inspectionRequired: row.inspection_required === true,
    notes: row.notes || null,
    isDefault: row.is_default === true,
    isActive: row.is_active === true,
    sortOrder: Number(row.sort_order || 0),
  };
}

function mapRequest(row) {
  const bookingPromotionSnapshot = row.booking_promotion_snapshot || null;
  return {
    id: Number(row.id),
    requestCode: row.request_code || null,
    customerUserId: Number(row.customer_user_id),
    providerId: Number(row.provider_id),
    offeringId: Number(row.offering_id),
    pricingOptionId: row.pricing_option_id == null ? null : Number(row.pricing_option_id),
    status: legacyServiceRequestStatus(row.status, row),
    requestedExecutionMode: row.requested_execution_mode || null,
    requestedDate: row.requested_date || null,
    requestedTime: row.requested_time || null,
    quantity: row.quantity == null ? null : Number(row.quantity),
    durationHours: row.duration_hours == null ? null : Number(row.duration_hours),
    notes: row.notes || null,
    addressLine: row.address_line || null,
    city: row.city || null,
    area: row.area || null,
    latitude: row.latitude == null ? null : Number(row.latitude),
    longitude: row.longitude == null ? null : Number(row.longitude),
    requiresHomeService: row.requires_home_service === true,
    requiresQuote: row.requires_quote === true,
    finalPrice: row.final_price == null ? null : Number(row.final_price),
    finalCurrency: row.final_currency || null,
    finalPricingModel: row.final_pricing_model || null,
    finalPricingUnit: row.final_pricing_unit || null,
    acceptedQuoteId: row.accepted_quote_id == null ? null : Number(row.accepted_quote_id),
    scheduledStartAt: row.scheduled_start_at || null,
    scheduledEndAt: row.scheduled_end_at || null,
    cancelReason: row.cancel_reason || null,
    rejectedReason: row.rejected_reason || null,
    completedAt: row.completed_at || null,
    bookingStatus: row.status || null,
    bookingVersion:
      row.booking_version == null ? null : Number(row.booking_version),
    bookingFlowKind: row.booking_flow_kind || null,
    bookingIdempotencyKey: row.booking_idempotency_key || null,
    bookingPricingType: row.booking_pricing_type || null,
    bookingPriceVersion: row.booking_price_version || null,
    bookingUnitPriceIqd:
      row.booking_unit_price_iqd == null ? null : Number(row.booking_unit_price_iqd),
    bookingQuantity:
      row.booking_quantity == null ? null : Number(row.booking_quantity),
    bookingDurationMinutes:
      row.booking_duration_minutes == null
        ? null
        : Number(row.booking_duration_minutes),
    bookingSubtotalIqd:
      row.booking_subtotal_iqd == null ? null : Number(row.booking_subtotal_iqd),
    bookingDiscountIqd:
      row.booking_discount_iqd == null ? null : Number(row.booking_discount_iqd),
    bookingServiceFeeIqd:
      row.booking_service_fee_iqd == null ? null : Number(row.booking_service_fee_iqd),
    bookingTotalIqd:
      row.booking_total_iqd == null ? null : Number(row.booking_total_iqd),
    bookingPromotionSnapshot:
      bookingPromotionSnapshot && typeof bookingPromotionSnapshot === 'object'
        ? bookingPromotionSnapshot
        : null,
    bookingExpiresAt: row.booking_expires_at || null,
    bookingProviderCompletedAt: row.booking_provider_completed_at || null,
    bookingFinalizationDueAt: row.booking_finalization_due_at || null,
    bookingFinalizedAt: row.booking_finalized_at || null,
    bookingTransitionNote: row.booking_transition_note || null,
    offeringName: row.offering_name || null,
    providerBusinessName: row.provider_business_name || null,
    customerFullName: row.customer_full_name || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapPromotion(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    providerId: Number(row.provider_id),
    title: row.title,
    description: row.description || null,
    discountType: normalizeServicePromotionType(row.discount_type) || row.discount_type,
    discountValue: row.discount_value == null ? null : Number(row.discount_value),
    specialPrice: row.special_price == null ? null : Number(row.special_price),
    startsAt: row.starts_at || null,
    endsAt: row.ends_at || null,
    badgeColor: row.badge_color || null,
    isActive: row.is_active === true,
  };
}

function isV2BookingRequest(dto = {}) {
  return Boolean(
    dto.pricingType ||
      dto.bookingPricingType ||
      dto.durationMinutes != null ||
      dto.expectedPriceVersion ||
      dto.idempotencyKey ||
      dto.expectedVersion != null
  );
}

function isDirectBookingV2(request = null) {
  return String(request?.booking_flow_kind || '').trim() === 'V2';
}

async function fetchBookingOfferingContext(client, { offeringId, providerId, pricingOptionId = null }) {
  const offeringR = await client.query(
    `SELECT
       o.*,
       p.business_name AS provider_business_name,
       p.city AS provider_city,
       p.area AS provider_area,
       p.provider_approval_status AS provider_approval_status,
       p.is_active AS provider_is_active,
       p.is_temporarily_paused AS provider_is_temporarily_paused
     FROM service_offerings o
     JOIN service_provider_profiles p ON p.id = o.provider_id
     WHERE o.id = $1
       AND o.provider_id = $2
     LIMIT 1`,
    [Number(offeringId), Number(providerId)]
  );
  const offering = offeringR.rows[0] || null;
  if (!offering) return null;

  const pricingR = await client.query(
    `SELECT *
     FROM service_pricing_options
     WHERE offering_id = $1
       AND is_active = TRUE
       AND ($2::bigint IS NULL OR id = $2)
     ORDER BY is_default DESC, sort_order ASC, id ASC
     LIMIT 1`,
    [Number(offeringId), pricingOptionId == null ? null : Number(pricingOptionId)]
  );
  const pricingOption = pricingR.rows[0] || null;

  const promoR = await client.query(
    `SELECT p.*
     FROM service_promotions p
     JOIN service_promotion_targets t ON t.promotion_id = p.id
     WHERE t.offering_id = $1
       AND p.provider_id = $2
       AND p.is_active = TRUE
       AND p.starts_at <= NOW()
       AND p.ends_at >= NOW()
     ORDER BY p.starts_at DESC, p.id DESC
     LIMIT 1`,
    [Number(offeringId), Number(providerId)]
  );
  const promotion = promoR.rows[0] || null;
  return { offering, pricingOption, promotion };
}

async function fetchExistingBookingByIdempotency(client, { customerUserId, idempotencyKey }) {
  const r = await client.query(
    `SELECT *
     FROM service_requests
     WHERE customer_user_id = $1
       AND booking_idempotency_key = $2
     LIMIT 1`,
    [Number(customerUserId), String(idempotencyKey)]
  );
  return r.rows[0] || null;
}

function mapQuote(row) {
  return {
    id: Number(row.id),
    requestId: Number(row.request_id),
    providerId: Number(row.provider_id),
    quotedByUserId: Number(row.quoted_by_user_id),
    roundNo: Number(row.round_no),
    quoteStatus: row.quote_status,
    pricingModel: row.pricing_model,
    pricingUnit: row.pricing_unit,
    amount: row.amount == null ? null : Number(row.amount),
    minAmount: row.min_amount == null ? null : Number(row.min_amount),
    maxAmount: row.max_amount == null ? null : Number(row.max_amount),
    visitFee: row.visit_fee == null ? null : Number(row.visit_fee),
    currency: row.currency || 'IQD',
    inspectionRequired: row.inspection_required === true,
    proposedVisitAt: row.proposed_visit_at || null,
    proposedStartAt: row.proposed_start_at || null,
    proposedEndAt: row.proposed_end_at || null,
    note: row.note || null,
    expiresAt: row.expires_at || null,
    respondedAt: row.responded_at || null,
    respondedByUserId:
      row.responded_by_user_id == null ? null : Number(row.responded_by_user_id),
    createdAt: row.created_at || null,
  };
}

function mapReview(row) {
  return {
    id: Number(row.id),
    requestId: Number(row.request_id),
    offeringId: Number(row.offering_id),
    providerId: Number(row.provider_id),
    customerUserId: Number(row.customer_user_id),
    rating: Number(row.rating),
    comment: row.comment || null,
    serviceAsDescribed: row.service_as_described,
    onTime: row.on_time,
    priceFair: row.price_fair,
    recommend: row.recommend,
    imageUrls: Array.isArray(row.image_urls_json) ? row.image_urls_json : [],
    customer: {
      id: Number(row.customer_user_id),
      fullName: row.customer_full_name || null,
      imageUrl: row.customer_image_url || null,
    },
    createdAt: row.created_at || null,
  };
}

function mapProviderSubscriptionOffer(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    requestId: Number(row.request_id),
    offeredByUserId:
      row.offered_by_user_id == null ? null : Number(row.offered_by_user_id),
    amount: row.amount == null ? null : Number(row.amount),
    currency: row.currency || 'IQD',
    title: row.title || null,
    description: row.description || null,
    validUntil: row.valid_until || null,
    status: row.status || 'pending_provider',
    providerResponseNote: row.provider_response_note || null,
    providerRespondedAt: row.provider_responded_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function mapProviderSubscriptionRequest(row, { offer = null } = {}) {
  if (!row) return null;
  return {
    id: Number(row.id),
    requestCode: row.request_code || null,
    fullName: row.full_name || null,
    businessName: row.business_name || null,
    phone: row.phone || null,
    logoUrl: row.logo_url || null,
    coverImageUrl: row.cover_image_url || null,
    mainCategoryId: row.main_category_id == null ? null : Number(row.main_category_id),
    mainCategoryName: row.main_category_name || null,
    city: row.city || null,
    area: row.area || null,
    addressLine: row.address_line || null,
    bio: row.bio || null,
    whatsappPhone: row.whatsapp_phone || null,
    servesAtHome: row.serves_at_home === true,
    servesAtShop: row.serves_at_shop === true,
    servesRemote: row.serves_remote === true,
    hasEmergencyService: row.has_emergency_service === true,
    bookingPolicy: row.booking_policy || 'approval_required',
    pricingMode: row.pricing_mode || 'mixed',
    yearsExperience:
      row.years_experience == null ? null : Number(row.years_experience),
    hasTeam: row.has_team === true,
    teamSize: row.team_size == null ? null : Number(row.team_size),
    acceptsCash: row.accepts_cash === true,
    acceptsElectronic: row.accepts_electronic === true,
    averageResponseMinutes:
      row.average_response_minutes == null
        ? null
        : Number(row.average_response_minutes),
    isAvailable247: row.is_available_24_7 === true,
    providerGender: row.provider_gender || null,
    languages: Array.isArray(row.languages_json) ? row.languages_json : [],
    areas: Array.isArray(row.areas_json) ? row.areas_json : [],
    availabilityRules: Array.isArray(row.availability_rules_json)
      ? row.availability_rules_json
      : [],
    status: row.status || 'pending_offer',
    statusNote: row.status_note || null,
    selectedOfferId:
      row.selected_offer_id == null ? null : Number(row.selected_offer_id),
    offeredAmount: row.offered_amount == null ? null : Number(row.offered_amount),
    offeredCurrency: row.offered_currency || null,
    offeredTitle: row.offered_title || null,
    offeredDescription: row.offered_description || null,
    offeredValidUntil: row.offered_valid_until || null,
    offerSentAt: row.offer_sent_at || null,
    offerAcceptedAt: row.offer_accepted_at || null,
    offerRejectedAt: row.offer_rejected_at || null,
    paymentConfirmedByUserId:
      row.payment_confirmed_by_user_id == null
        ? null
        : Number(row.payment_confirmed_by_user_id),
    paymentConfirmedAt: row.payment_confirmed_at || null,
    accountCreatedUserId:
      row.account_created_user_id == null
        ? null
        : Number(row.account_created_user_id),
    accountCreatedAt: row.account_created_at || null,
    reviewedByUserId:
      row.reviewed_by_user_id == null ? null : Number(row.reviewed_by_user_id),
    reviewedAt: row.reviewed_at || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
    activeOffer: offer || null,
  };
}

async function fetchPricingMap(client, offeringIds = []) {
  const ids = offeringIds
    .map((id) => Number(id))
    .filter((id) => Number.isInteger(id) && id > 0);
  if (!ids.length) return new Map();
  const r = await client.query(
    `SELECT *
     FROM service_pricing_options
     WHERE offering_id = ANY($1::bigint[])
       AND is_active = TRUE
     ORDER BY offering_id ASC, is_default DESC, sort_order ASC, id ASC`,
    [ids]
  );
  const map = new Map();
  for (const row of r.rows) {
    const offeringId = Number(row.offering_id);
    const list = map.get(offeringId) || [];
    list.push(mapPricing(row));
    map.set(offeringId, list);
  }
  return map;
}

async function fetchMediaMap(client, offeringIds = []) {
  const ids = offeringIds
    .map((id) => Number(id))
    .filter((id) => Number.isInteger(id) && id > 0);
  if (!ids.length) return new Map();
  const r = await client.query(
    `SELECT *
     FROM service_offering_media
     WHERE offering_id = ANY($1::bigint[])
     ORDER BY offering_id ASC, sort_order ASC, id ASC`,
    [ids]
  );
  const map = new Map();
  for (const row of r.rows) {
    const offeringId = Number(row.offering_id);
    const list = map.get(offeringId) || [];
    list.push({
      id: Number(row.id),
      offeringId,
      mediaUrl: row.media_url,
      mediaKind: row.media_kind || 'image',
      sortOrder: Number(row.sort_order || 0),
      createdAt: row.created_at || null,
    });
    map.set(offeringId, list);
  }
  return map;
}

async function fetchActivePromotionMap(client, providerIds = []) {
  const ids = providerIds
    .map((id) => Number(id))
    .filter((id) => Number.isInteger(id) && id > 0);
  if (!ids.length) return new Map();
  const r = await client.query(
    `SELECT *
     FROM service_promotions
     WHERE provider_id = ANY($1::bigint[])
       AND is_active = TRUE
       AND starts_at <= NOW()
       AND ends_at >= NOW()
     ORDER BY provider_id ASC, starts_at DESC`,
    [ids]
  );
  const map = new Map();
  for (const row of r.rows) {
    const providerId = Number(row.provider_id);
    const list = map.get(providerId) || [];
    list.push({
      id: Number(row.id),
      providerId,
      title: row.title,
      description: row.description || null,
      discountType: normalizeServicePromotionType(row.discount_type) || row.discount_type,
      discountValue: row.discount_value == null ? null : Number(row.discount_value),
      specialPrice: row.special_price == null ? null : Number(row.special_price),
      startsAt: row.starts_at || null,
      endsAt: row.ends_at || null,
      badgeColor: row.badge_color || null,
      isActive: row.is_active === true,
    });
    map.set(providerId, list);
  }
  return map;
}

async function findOwnerProviderByUserIdInternal(client, userId) {
  const uid = toInt(userId);
  if (!uid) return null;
  const r = await client.query(
     `SELECT
       p.*,
       c.name AS main_category_name,
       u.id AS owner_id,
       u.full_name AS owner_full_name,
       u.image_url AS owner_image_url
     FROM service_provider_profiles p
     LEFT JOIN service_categories c ON c.id = p.main_category_id
     LEFT JOIN app_user u ON u.id = p.user_id
     WHERE p.user_id = $1
     LIMIT 1`,
    [uid]
  );
  return mapProvider(r.rows[0] || null);
}

async function findProviderEmployeeAccessByUserId(client, userId) {
  const uid = toInt(userId);
  if (!uid) return null;
  const r = await client.query(
    `SELECT
       p.*,
       c.name AS main_category_name,
       u.id AS owner_id,
       u.full_name AS owner_full_name,
       u.image_url AS owner_image_url,
       ep.id AS employee_profile_id,
       ep.role_tag AS employee_role_tag,
       ep.display_name AS employee_display_name,
       ep.contact_email AS employee_contact_email,
       ep.permissions_json,
       ep.is_active AS employee_is_active,
       ep.archived_at AS employee_archived_at,
       ep.notes,
       ep.invited_by_user_id,
       ep.updated_by_user_id
     FROM service_provider_employee_profile ep
     JOIN service_provider_profiles p ON p.id = ep.provider_id
     LEFT JOIN service_categories c ON c.id = p.main_category_id
     LEFT JOIN app_user u ON u.id = p.user_id
     WHERE ep.employee_user_id = $1
       AND ep.is_active = TRUE
       AND ep.archived_at IS NULL
       AND p.is_active = TRUE
     ORDER BY ep.updated_at DESC, ep.id DESC
     LIMIT 1`,
    [uid]
  );
  return r.rows[0] || null;
}

async function getProviderByUserId(client, userId) {
  const direct = await findOwnerProviderByUserIdInternal(client, userId);
  if (direct) return direct;
  const employee = await findProviderEmployeeAccessByUserId(client, userId);
  return employee ? mapProvider(employee) : null;
}

async function getProviderById(client, providerId) {
  const pid = toInt(providerId);
  if (!pid) return null;
  const r = await client.query(
    `SELECT
       p.*,
       c.name AS main_category_name,
       u.id AS owner_id,
       u.full_name AS owner_full_name,
       u.image_url AS owner_image_url
     FROM service_provider_profiles p
     LEFT JOIN service_categories c ON c.id = p.main_category_id
     LEFT JOIN app_user u ON u.id = p.user_id
     WHERE p.id = $1
     LIMIT 1`,
    [pid]
  );
  return mapProvider(r.rows[0] || null);
}

export async function getProviderByIdForAdmin(providerId) {
  const client = await pool.connect();
  try {
    return await getProviderById(client, providerId);
  } finally {
    client.release();
  }
}

function buildSort(sort) {
  switch (String(sort || '').trim().toLowerCase()) {
    case 'cheapest':
      return 'COALESCE(po.amount, 999999999) ASC, o.created_at DESC';
    case 'rating_desc':
      return 'COALESCE(p.rating_avg, 0) DESC, COALESCE(p.rating_count, 0) DESC, o.created_at DESC';
    case 'fastest_response':
      return 'COALESCE(p.average_response_minutes, 999999) ASC, o.created_at DESC';
    case 'most_completed':
      return 'COALESCE(p.completed_orders_count, 0) DESC, o.created_at DESC';
    default:
      return 'o.created_at DESC, o.id DESC';
  }
}

function buildSearchFilters(query, params) {
  const filters = [
    `o.is_active = TRUE`,
    `o.is_temporarily_paused = FALSE`,
    `o.moderation_status = 'approved'`,
    `p.is_active = TRUE`,
    `p.is_temporarily_paused = FALSE`,
    `p.provider_approval_status = 'approved'`,
  ];

  if (query.categoryId) {
    params.push(Number(query.categoryId));
    filters.push(`o.main_category_id = $${params.length}`);
  }
  if (query.subcategoryId) {
    params.push(Number(query.subcategoryId));
    filters.push(`o.subcategory_id = $${params.length}`);
  }
  if (query.city) {
    params.push(`%${query.city}%`);
    filters.push(`COALESCE(p.city, '') ILIKE $${params.length}`);
  }
  if (query.area) {
    params.push(`%${query.area}%`);
    filters.push(`COALESCE(p.area, '') ILIKE $${params.length}`);
  }
  if (query.ratingMin != null) {
    params.push(Number(query.ratingMin));
    filters.push(`COALESCE(p.rating_avg, 0) >= $${params.length}`);
  }
  if (query.homeService === true) {
    filters.push(`p.serves_at_home = TRUE`);
  }
  if (query.emergency === true) {
    filters.push(`p.has_emergency_service = TRUE`);
  }
  if (query.offersOnly === true) {
    filters.push(`EXISTS (
      SELECT 1
      FROM service_promotions spm
      WHERE spm.provider_id = p.id
        AND spm.is_active = TRUE
        AND spm.starts_at <= NOW()
        AND spm.ends_at >= NOW()
    )`);
  }
  if (query.q) {
    params.push(query.q);
    filters.push(`(
      o.search_vector @@ plainto_tsquery('simple', $${params.length})
      OR p.search_vector @@ plainto_tsquery('simple', $${params.length})
      OR o.name ILIKE ('%' || $${params.length} || '%')
      OR p.business_name ILIKE ('%' || $${params.length} || '%')
      OR COALESCE(o.description, '') ILIKE ('%' || $${params.length} || '%')
    )`);
  }
  return filters;
}

export async function listPublicCategories({ q: search = '' } = {}) {
  const r = await q(
    `SELECT *
     FROM service_categories
     WHERE is_active = TRUE
       AND is_public = TRUE
     ORDER BY level ASC, sort_order ASC, name ASC`
  );
  return filterCategoryTree(buildCategoryTree(r.rows), search);
}

export async function getPublicCategoryById(id) {
  const categoryId = toInt(id);
  if (!categoryId) return null;
  const r = await q(
    `SELECT *
     FROM service_categories
     WHERE id = $1
       AND is_active = TRUE
       AND is_public = TRUE
     LIMIT 1`,
    [categoryId]
  );
  return mapCategory(r.rows[0] || null);
}

export async function createPublicCategory({ userId, name, parentCategoryId = null }) {
  const actorUserId = toInt(userId);
  const categoryName = String(name || '').trim();
  const normalizedParentId = toInt(parentCategoryId);
  if (!actorUserId || !categoryName) return null;

  const params = [categoryName, actorUserId];
  let sql;
  if (normalizedParentId) {
    params.push(normalizedParentId);
    sql = `WITH parent AS (
             SELECT id
             FROM service_categories
             WHERE id = $3
               AND level = 1
               AND parent_id IS NULL
               AND is_active = TRUE
               AND is_public = TRUE
             LIMIT 1
           ),
           next_sort AS (
             SELECT COALESCE(MAX(sort_order), 0) + 1 AS next_sort
             FROM service_categories
             WHERE parent_id = $3
           )
           INSERT INTO service_categories (
             parent_id,
             level,
             name,
             sort_order,
             is_active,
             is_public,
             created_by_user_id,
             created_at,
             updated_at
           )
           SELECT
             parent.id,
             2,
             $1,
             next_sort,
             TRUE,
             TRUE,
             $2,
             NOW(),
             NOW()
           FROM parent, next_sort
           ON CONFLICT (parent_id_resolved, normalized_name)
           DO UPDATE SET
             name = EXCLUDED.name,
             is_active = TRUE,
             is_public = TRUE,
             created_by_user_id = COALESCE(service_categories.created_by_user_id, EXCLUDED.created_by_user_id),
             updated_at = NOW()
           RETURNING *`;
  } else {
    sql = `WITH next_sort AS (
             SELECT COALESCE(MAX(sort_order), 0) + 1 AS next_sort
             FROM service_categories
             WHERE parent_id IS NULL
           )
           INSERT INTO service_categories (
             parent_id,
             level,
             name,
             sort_order,
             is_active,
             is_public,
             created_by_user_id,
             created_at,
             updated_at
           )
           SELECT
             NULL,
             1,
             $1,
             next_sort,
             TRUE,
             TRUE,
             $2,
             NOW(),
             NOW()
           FROM next_sort
           ON CONFLICT (parent_id_resolved, normalized_name)
           DO UPDATE SET
             name = EXCLUDED.name,
             is_active = TRUE,
             is_public = TRUE,
             created_by_user_id = COALESCE(service_categories.created_by_user_id, EXCLUDED.created_by_user_id),
             updated_at = NOW()
           RETURNING *`;
  }

  const r = await q(sql, params);

  const row = r.rows[0] || null;
  if (!row) return null;
  return { ...mapCategory(row), children: [] };
}

export async function searchPublicOfferings(query = {}, { viewerUserId = null } = {}) {
  const client = await pool.connect();
  try {
    const params = [];
    const filters = buildSearchFilters(query, params);
    const orderBy = buildSort(query.sort);
    params.push(Math.max(1, Math.min(100, Number(query.limit) || 20)));
    params.push(Math.max(0, Number(query.offset) || 0));

    const r = await client.query(
      `SELECT
         o.*,
         mc.name AS main_category_name,
         sc.name AS subcategory_name,
         p.business_name AS provider_business_name,
         p.city AS provider_city,
         p.area AS provider_area,
         p.rating_avg AS provider_rating_avg,
         p.rating_count AS provider_rating_count,
         p.completed_orders_count AS provider_completed_orders_count,
         p.has_emergency_service AS provider_has_emergency_service,
         p.is_featured AS provider_is_featured,
         p.logo_url AS provider_logo_url,
         p.provider_approval_status AS provider_approval_status,
         p.average_response_minutes AS provider_average_response_minutes,
         p.is_temporarily_paused AS provider_is_temporarily_paused
       FROM service_offerings o
       JOIN service_provider_profiles p ON p.id = o.provider_id
       LEFT JOIN service_categories mc ON mc.id = o.main_category_id
       LEFT JOIN service_categories sc ON sc.id = o.subcategory_id
       LEFT JOIN LATERAL (
         SELECT amount
         FROM service_pricing_options po
         WHERE po.offering_id = o.id
           AND po.is_active = TRUE
         ORDER BY po.is_default DESC, po.sort_order ASC, po.id ASC
         LIMIT 1
       ) po ON TRUE
       WHERE ${filters.join(' AND ')}
       ORDER BY ${orderBy}
       LIMIT $${params.length - 1}
       OFFSET $${params.length}`,
      params
    );

    const offerings = r.rows.map(mapOffering);
    const offeringIds = offerings.map((x) => x.id);
    const providerIds = offerings.map((x) => x.providerId);
    const pricingMap = await fetchPricingMap(client, offeringIds);
    const mediaMap = await fetchMediaMap(client, offeringIds);
    const promoMap = await fetchActivePromotionMap(client, providerIds);

    return offerings.map((offering) => ({
      ...offering,
      pricingOptions: pricingMap.get(offering.id) || [],
      media: mediaMap.get(offering.id) || [],
      activePromotions: promoMap.get(offering.providerId) || [],
      hasActivePromotion: (promoMap.get(offering.providerId) || []).length > 0,
      isSavedOffering: false,
      isSavedProvider: false,
      _viewerUserId: viewerUserId || null,
    }));
  } finally {
    client.release();
  }
}

export async function getPublicProviderById(providerId) {
  const client = await pool.connect();
  try {
    const provider = await getProviderById(client, providerId);
    if (!provider) return null;
    if (
      provider.providerApprovalStatus !== 'approved' ||
      !provider.isActive ||
      provider.isTemporarilyPaused
    ) {
      return null;
    }

    const areasR = await client.query(
      `SELECT city, area, note
       FROM service_provider_areas
       WHERE provider_id = $1
       ORDER BY city ASC, area ASC NULLS LAST`,
      [Number(providerId)]
    );
    const availabilityR = await client.query(
      `SELECT day_of_week, start_time, end_time, is_active
       FROM service_provider_availability_rules
       WHERE provider_id = $1
       ORDER BY day_of_week ASC, start_time ASC`,
      [Number(providerId)]
    );
    const offeringsR = await client.query(
      `SELECT
         o.*,
         mc.name AS main_category_name,
         sc.name AS subcategory_name,
         p.business_name AS provider_business_name,
         p.city AS provider_city,
         p.area AS provider_area,
         p.rating_avg AS provider_rating_avg,
         p.rating_count AS provider_rating_count,
         p.completed_orders_count AS provider_completed_orders_count,
         p.has_emergency_service AS provider_has_emergency_service,
         p.is_featured AS provider_is_featured,
         p.logo_url AS provider_logo_url,
         p.provider_approval_status AS provider_approval_status,
         p.average_response_minutes AS provider_average_response_minutes,
         p.is_temporarily_paused AS provider_is_temporarily_paused
       FROM service_offerings o
       JOIN service_provider_profiles p ON p.id = o.provider_id
       LEFT JOIN service_categories mc ON mc.id = o.main_category_id
       LEFT JOIN service_categories sc ON sc.id = o.subcategory_id
       WHERE o.provider_id = $1
         AND o.is_active = TRUE
         AND o.is_temporarily_paused = FALSE
         AND o.moderation_status = 'approved'
       ORDER BY o.created_at DESC`,
      [Number(providerId)]
    );
    const promotionsR = await client.query(
      `SELECT *
       FROM service_promotions
       WHERE provider_id = $1
         AND is_active = TRUE
         AND starts_at <= NOW()
         AND ends_at >= NOW()
       ORDER BY starts_at DESC`,
      [Number(providerId)]
    );
    const portfolioR = await client.query(
      `SELECT *
       FROM service_portfolio_items
       WHERE provider_id = $1
       ORDER BY is_pinned DESC, sort_order ASC, id DESC
       LIMIT 100`,
      [Number(providerId)]
    );
    const reviewsR = await client.query(
      `SELECT
         r.*,
         u.full_name AS customer_full_name,
         u.image_url AS customer_image_url
       FROM service_reviews r
       JOIN app_user u ON u.id = r.customer_user_id
       WHERE r.provider_id = $1
       ORDER BY r.created_at DESC
       LIMIT 80`,
      [Number(providerId)]
    );

    const offerings = offeringsR.rows.map(mapOffering);
    const offeringIds = offerings.map((x) => x.id);
    const pricingMap = await fetchPricingMap(client, offeringIds);
    const mediaMap = await fetchMediaMap(client, offeringIds);

    return {
      ...provider,
      areas: areasR.rows.map((x) => ({
        city: x.city,
        area: x.area || null,
        note: x.note || null,
      })),
      availabilityRules: availabilityR.rows.map((x) => ({
        dayOfWeek: Number(x.day_of_week),
        startTime: x.start_time,
        endTime: x.end_time,
        isActive: x.is_active === true,
      })),
      offerings: offerings.map((offering) => ({
        ...offering,
        pricingOptions: pricingMap.get(offering.id) || [],
        media: mediaMap.get(offering.id) || [],
      })),
      activePromotions: promotionsR.rows.map((x) => ({
        id: Number(x.id),
        providerId: Number(x.provider_id),
        title: x.title,
        description: x.description || null,
        discountType: x.discount_type,
        discountValue: x.discount_value == null ? null : Number(x.discount_value),
        specialPrice: x.special_price == null ? null : Number(x.special_price),
        startsAt: x.starts_at || null,
        endsAt: x.ends_at || null,
        badgeColor: x.badge_color || null,
        isActive: x.is_active === true,
      })),
      portfolio: portfolioR.rows.map((x) => ({
        id: Number(x.id),
        providerId: Number(x.provider_id),
        offeringId: x.offering_id == null ? null : Number(x.offering_id),
        title: x.title || null,
        description: x.description || null,
        mediaUrl: x.media_url,
        mediaKind: x.media_kind || 'image',
        beforeMediaUrl: x.before_media_url || null,
        afterMediaUrl: x.after_media_url || null,
        sortOrder: Number(x.sort_order || 0),
        isPinned: x.is_pinned === true,
        createdAt: x.created_at || null,
      })),
      reviews: reviewsR.rows.map(mapReview),
    };
  } finally {
    client.release();
  }
}

export async function getPublicOfferingById(offeringId) {
  const oid = toInt(offeringId);
  if (!oid) return null;
  const client = await pool.connect();
  try {
    const r = await client.query(
      `SELECT
         o.*,
         mc.name AS main_category_name,
         sc.name AS subcategory_name,
         p.business_name AS provider_business_name,
         p.city AS provider_city,
         p.area AS provider_area,
         p.rating_avg AS provider_rating_avg,
         p.rating_count AS provider_rating_count,
         p.completed_orders_count AS provider_completed_orders_count,
         p.has_emergency_service AS provider_has_emergency_service,
         p.is_featured AS provider_is_featured,
         p.logo_url AS provider_logo_url,
         p.provider_approval_status AS provider_approval_status,
         p.average_response_minutes AS provider_average_response_minutes,
         p.is_temporarily_paused AS provider_is_temporarily_paused
       FROM service_offerings o
       JOIN service_provider_profiles p ON p.id = o.provider_id
       LEFT JOIN service_categories mc ON mc.id = o.main_category_id
       LEFT JOIN service_categories sc ON sc.id = o.subcategory_id
       WHERE o.id = $1
       LIMIT 1`,
      [oid]
    );
    const offering = mapOffering(r.rows[0] || null);
    if (!offering) return null;
    if (
      offering.moderationStatus !== 'approved' ||
      !offering.isActive ||
      offering.isTemporarilyPaused ||
      offering.provider.approvalStatus !== 'approved' ||
      offering.provider.isTemporarilyPaused
    ) {
      return null;
    }

    const pricingMap = await fetchPricingMap(client, [offering.id]);
    const mediaMap = await fetchMediaMap(client, [offering.id]);
    const promoMap = await fetchActivePromotionMap(client, [offering.providerId]);
    const reviewsR = await client.query(
      `SELECT
         r.*,
         u.full_name AS customer_full_name,
         u.image_url AS customer_image_url
       FROM service_reviews r
       JOIN app_user u ON u.id = r.customer_user_id
       WHERE r.offering_id = $1
       ORDER BY r.created_at DESC
       LIMIT 40`,
      [offering.id]
    );

    return {
      ...offering,
      pricingOptions: pricingMap.get(offering.id) || [],
      media: mediaMap.get(offering.id) || [],
      activePromotions: promoMap.get(offering.providerId) || [],
      reviews: reviewsR.rows.map(mapReview),
    };
  } finally {
    client.release();
  }
}

export async function getServiceOfferingByIdForContext(offeringId) {
  const id = toInt(offeringId);
  if (!id) return null;
  const r = await q(
    `SELECT
       o.id,
       o.provider_id,
       o.name,
       o.description,
       o.moderation_status,
       o.is_active,
       o.created_at,
       p.user_id AS provider_user_id,
       p.business_name AS provider_business_name,
       p.city AS provider_city,
       p.provider_approval_status,
       p.is_active AS provider_is_active
     FROM service_offerings o
     JOIN service_provider_profiles p ON p.id = o.provider_id
     WHERE o.id = $1
     LIMIT 1`,
    [id]
  );
  const row = r.rows[0] || null;
  if (!row) return null;
  return {
    id: Number(row.id),
    ownerUserId: Number(row.provider_user_id),
    providerId: Number(row.provider_id),
    title: row.name,
    subtitle: row.provider_business_name || null,
    city: row.provider_city || null,
    description: row.description || null,
    status:
      row.is_active === true &&
      row.moderation_status === 'approved' &&
      row.provider_approval_status === 'approved' &&
      row.provider_is_active === true
        ? 'active'
        : row.is_active === true
        ? 'pending'
        : 'archived',
  };
}

export async function getServiceProviderByIdForContext(providerId) {
  const id = toInt(providerId);
  if (!id) return null;
  const r = await q(
    `SELECT
       p.id,
       p.user_id,
       p.business_name,
       p.city,
       p.area,
       p.provider_approval_status,
       p.is_active
     FROM service_provider_profiles p
     WHERE p.id = $1
     LIMIT 1`,
    [id]
  );
  const row = r.rows[0] || null;
  if (!row) return null;
  return {
    id: Number(row.id),
    ownerUserId: Number(row.user_id),
    title: row.business_name,
    subtitle: [row.city, row.area].filter(Boolean).join(' • ') || null,
    city: row.city || null,
    status:
      row.provider_approval_status === 'approved' && row.is_active === true
        ? 'active'
        : row.is_active === true
        ? 'pending'
        : 'archived',
  };
}

export async function getServiceRequestByIdForContext(requestId) {
  const id = toInt(requestId);
  if (!id) return null;
  const r = await q(
    `SELECT
       sr.id,
       sr.status,
       sr.customer_user_id,
       sr.provider_id,
       sp.user_id AS provider_user_id,
       so.name AS offering_name,
       sp.business_name AS provider_business_name,
       sp.city AS provider_city
     FROM service_requests sr
     JOIN service_provider_profiles sp ON sp.id = sr.provider_id
     JOIN service_offerings so ON so.id = sr.offering_id
     WHERE sr.id = $1
     LIMIT 1`,
    [id]
  );
  const row = r.rows[0] || null;
  if (!row) return null;
  return {
    id: Number(row.id),
    customerUserId: Number(row.customer_user_id),
    providerUserId: Number(row.provider_user_id),
    providerId: Number(row.provider_id),
    title: row.offering_name,
    subtitle: row.provider_business_name || null,
    city: row.provider_city || null,
    status: row.status || 'unavailable',
  };
}

export async function getProviderProfileByUserId(userId) {
  const client = await pool.connect();
  try {
    return await getProviderByUserId(client, userId);
  } finally {
    client.release();
  }
}

export async function findOwnerProviderByUserId(userId) {
  const client = await pool.connect();
  try {
    return await findOwnerProviderByUserIdInternal(client, userId);
  } finally {
    client.release();
  }
}

export async function findProviderByEmployeeUserId(userId) {
  const client = await pool.connect();
  try {
    const row = await findProviderEmployeeAccessByUserId(client, userId);
    if (!row) return null;
    return {
      provider: mapProvider(row),
      employeeProfile: {
        id: row.employee_profile_id == null ? null : Number(row.employee_profile_id),
        roleTag: row.employee_role_tag || 'staff',
        displayName: row.employee_display_name || null,
        contactEmail: row.employee_contact_email || null,
        permissions: Array.isArray(row.permissions_json) ? row.permissions_json : [],
        permissionMap: Object.fromEntries(
          (Array.isArray(row.permissions_json) ? row.permissions_json : []).map(
            (permission) => [String(permission || ''), true]
          )
        ),
        isActive: row.employee_is_active === true,
        archivedAt: row.employee_archived_at || null,
        notes: row.notes || null,
        invitedByUserId:
          row.invited_by_user_id == null ? null : Number(row.invited_by_user_id),
        updatedByUserId:
          row.updated_by_user_id == null ? null : Number(row.updated_by_user_id),
      },
    };
  } finally {
    client.release();
  }
}

async function replaceProviderAreas(client, providerId, areas = []) {
  await client.query(`DELETE FROM service_provider_areas WHERE provider_id = $1`, [
    Number(providerId),
  ]);
  for (const item of areas) {
    if (!item?.city) continue;
    await client.query(
      `INSERT INTO service_provider_areas (provider_id, city, area, note)
       VALUES ($1,$2,$3,$4)
       ON CONFLICT (provider_id, city, area)
       DO UPDATE SET note = EXCLUDED.note`,
      [Number(providerId), item.city, item.area || null, item.note || null]
    );
  }
}

async function replaceAvailability(client, providerId, rules = []) {
  await client.query(
    `DELETE FROM service_provider_availability_rules WHERE provider_id = $1`,
    [Number(providerId)]
  );
  for (const item of rules) {
    if (item?.dayOfWeek == null || !item?.startTime || !item?.endTime) continue;
    await client.query(
      `INSERT INTO service_provider_availability_rules (
         provider_id, day_of_week, start_time, end_time, is_active
       )
       VALUES ($1,$2,$3,$4,$5)`,
      [
        Number(providerId),
        Number(item.dayOfWeek),
        item.startTime,
        item.endTime,
        item.isActive !== false,
      ]
    );
  }
}

export async function createProviderProfile({
  userId,
  dto,
  assets = {},
  moderation = {},
}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const approvalStatus = moderation.approvalStatus || 'pending';
    const approvalNote = moderation.approvalNote || null;
    const approvedByUserId = toInt(moderation.approvedByUserId);
    const approvedAt =
      moderation.approvedAt != null ? toIsoOrNull(moderation.approvedAt) : null;
    const r = await client.query(
      `INSERT INTO service_provider_profiles (
         user_id,
         business_name,
         logo_url,
         cover_image_url,
         main_category_id,
         bio,
         phone,
         whatsapp_phone,
         city,
         area,
         address_line,
         serves_at_home,
         serves_at_shop,
         serves_remote,
         has_emergency_service,
         booking_policy,
         pricing_mode,
         years_experience,
         has_team,
         team_size,
         accepts_cash,
         accepts_electronic,
         average_response_minutes,
         is_available_24_7,
         provider_gender,
         languages_json,
         search_text,
         provider_approval_status,
         approval_note,
         approved_by_user_id,
         approved_at,
         created_at,
         updated_at
       )
       VALUES (
         $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,
         $21,$22,$23,$24,$25,$26::jsonb,$27,$28,$29,$30,$31,NOW(),NOW()
       )
       RETURNING id`,
      [
        Number(userId),
        dto.businessName,
        assets.logoUrl || null,
        assets.coverImageUrl || null,
        dto.mainCategoryId,
        dto.bio || null,
        dto.phone,
        dto.whatsappPhone || null,
        dto.city,
        dto.area || null,
        dto.addressLine || null,
        dto.servesAtHome === true,
        dto.servesAtShop === true,
        dto.servesRemote === true,
        dto.hasEmergencyService === true,
        dto.bookingPolicy || 'approval_required',
        dto.pricingMode || 'mixed',
        dto.yearsExperience == null ? null : Number(dto.yearsExperience),
        dto.hasTeam === true,
        dto.teamSize == null ? null : Number(dto.teamSize),
        dto.acceptsCash !== false,
        dto.acceptsElectronic === true,
        dto.averageResponseMinutes == null ? null : Number(dto.averageResponseMinutes),
        dto.available247 === true,
        dto.providerGender || null,
        JSON.stringify(Array.isArray(dto.languages) ? dto.languages : []),
        dto.bio || dto.businessName,
        approvalStatus,
        approvalNote,
        approvedByUserId,
        approvedAt,
      ]
    );
    const providerId = Number(r.rows[0].id);
    await replaceProviderAreas(client, providerId, dto.areas || []);
    await replaceAvailability(client, providerId, dto.availabilityRules || []);
    await client.query('COMMIT');
    return await getProviderByUserId(client, userId);
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function updateProviderProfile({ userId, dto, assets = {} }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const provider = await getProviderByUserId(client, userId);
    if (!provider) {
      await client.query('ROLLBACK');
      return null;
    }

    await client.query(
      `UPDATE service_provider_profiles
       SET
         business_name = COALESCE($2, business_name),
         logo_url = COALESCE($3, logo_url),
         cover_image_url = COALESCE($4, cover_image_url),
         main_category_id = COALESCE($5, main_category_id),
         bio = COALESCE($6, bio),
         phone = COALESCE($7, phone),
         whatsapp_phone = COALESCE($8, whatsapp_phone),
         city = COALESCE($9, city),
         area = COALESCE($10, area),
         address_line = CASE WHEN $11::text IS NULL THEN address_line ELSE $11 END,
         serves_at_home = COALESCE($12, serves_at_home),
         serves_at_shop = COALESCE($13, serves_at_shop),
         serves_remote = COALESCE($14, serves_remote),
         has_emergency_service = COALESCE($15, has_emergency_service),
         booking_policy = COALESCE($16, booking_policy),
         pricing_mode = COALESCE($17, pricing_mode),
         years_experience = COALESCE($18, years_experience),
         has_team = COALESCE($19, has_team),
         team_size = COALESCE($20, team_size),
         accepts_cash = COALESCE($21, accepts_cash),
         accepts_electronic = COALESCE($22, accepts_electronic),
         average_response_minutes = COALESCE($23, average_response_minutes),
         is_available_24_7 = COALESCE($24, is_available_24_7),
         provider_gender = CASE WHEN $25::text IS NULL THEN provider_gender ELSE $25 END,
         languages_json = COALESCE($26::jsonb, languages_json),
         search_text = COALESCE($27, search_text),
         updated_at = NOW()
       WHERE user_id = $1`,
      [
        Number(userId),
        dto.businessName || null,
        assets.logoUrl || null,
        assets.coverImageUrl || null,
        dto.mainCategoryId || null,
        dto.bio || null,
        dto.phone || null,
        dto.whatsappPhone || null,
        dto.city || null,
        dto.area || null,
        dto.addressLine,
        dto.servesAtHome,
        dto.servesAtShop,
        dto.servesRemote,
        dto.hasEmergencyService,
        dto.bookingPolicy || null,
        dto.pricingMode || null,
        dto.yearsExperience == null ? null : Number(dto.yearsExperience),
        dto.hasTeam,
        dto.teamSize == null ? null : Number(dto.teamSize),
        dto.acceptsCash,
        dto.acceptsElectronic,
        dto.averageResponseMinutes == null ? null : Number(dto.averageResponseMinutes),
        dto.available247,
        dto.providerGender,
        dto.languages ? JSON.stringify(dto.languages) : null,
        dto.searchText || dto.bio || null,
      ]
    );

    if (Array.isArray(dto.areas)) {
      await replaceProviderAreas(client, provider.id, dto.areas);
    }
    if (Array.isArray(dto.availabilityRules)) {
      await replaceAvailability(client, provider.id, dto.availabilityRules);
    }

    await client.query('COMMIT');
    return await getProviderByUserId(client, userId);
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

async function getOfferingForProvider(client, providerId, offeringId) {
  const r = await client.query(
    `SELECT
       o.*,
       mc.name AS main_category_name,
       sc.name AS subcategory_name,
       p.business_name AS provider_business_name,
       p.city AS provider_city,
       p.area AS provider_area,
       p.rating_avg AS provider_rating_avg,
       p.rating_count AS provider_rating_count,
       p.completed_orders_count AS provider_completed_orders_count,
       p.has_emergency_service AS provider_has_emergency_service,
       p.is_featured AS provider_is_featured,
       p.logo_url AS provider_logo_url,
       p.provider_approval_status AS provider_approval_status,
       p.average_response_minutes AS provider_average_response_minutes,
       p.is_temporarily_paused AS provider_is_temporarily_paused
     FROM service_offerings o
     JOIN service_provider_profiles p ON p.id = o.provider_id
     LEFT JOIN service_categories mc ON mc.id = o.main_category_id
     LEFT JOIN service_categories sc ON sc.id = o.subcategory_id
     WHERE o.id = $1
       AND o.provider_id = $2
     LIMIT 1`,
    [Number(offeringId), Number(providerId)]
  );
  const offering = mapOffering(r.rows[0] || null);
  if (!offering) return null;
  const pricingMap = await fetchPricingMap(client, [offering.id]);
  const mediaMap = await fetchMediaMap(client, [offering.id]);
  return {
    ...offering,
    pricingOptions: pricingMap.get(offering.id) || [],
    media: mediaMap.get(offering.id) || [],
  };
}

async function replacePricingOptions(client, offeringId, options = []) {
  await client.query(`DELETE FROM service_pricing_options WHERE offering_id = $1`, [
    Number(offeringId),
  ]);
  if (!Array.isArray(options) || options.length === 0) return;
  let hasDefault = false;
  for (const item of options) {
    if (item?.isDefault === true) {
      hasDefault = true;
      break;
    }
  }
  for (let i = 0; i < options.length; i += 1) {
    const item = options[i] || {};
    await client.query(
      `INSERT INTO service_pricing_options (
         offering_id,
         pricing_model,
         pricing_unit,
         label,
         amount,
         min_amount,
         max_amount,
         visit_fee,
         currency,
         min_quantity,
         max_quantity,
         inspection_required,
         notes,
         is_default,
         is_active,
         sort_order,
         created_at,
         updated_at
       )
       VALUES (
         $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,NOW(),NOW()
       )`,
      [
        Number(offeringId),
        item.pricingModel,
        item.pricingUnit,
        item.label || null,
        item.amount == null ? null : Number(item.amount),
        item.minAmount == null ? null : Number(item.minAmount),
        item.maxAmount == null ? null : Number(item.maxAmount),
        item.visitFee == null ? null : Number(item.visitFee),
        item.currency || 'IQD',
        item.minQuantity == null ? null : Number(item.minQuantity),
        item.maxQuantity == null ? null : Number(item.maxQuantity),
        item.inspectionRequired === true,
        item.notes || null,
        hasDefault ? item.isDefault === true : i === 0,
        item.isActive !== false,
        item.sortOrder == null ? i : Number(item.sortOrder),
      ]
    );
  }
}

export async function createOfferingForProvider({ userId, dto, mediaUrls = [] }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const provider = await getProviderByUserId(client, userId);
    if (!provider) {
      await client.query('ROLLBACK');
      return null;
    }
    const r = await client.query(
      `INSERT INTO service_offerings (
         provider_id,
         main_category_id,
         subcategory_id,
         name,
         description,
         execution_mode,
         requires_schedule,
         requires_provider_approval,
         estimated_duration_minutes,
         has_fixed_price,
         starts_from_price,
         inspection_required,
         custom_quote_only,
         workers_count,
         includes_text,
         excludes_text,
         materials_text,
         notes,
         supports_hourly_booking,
         supports_daily_booking,
         supports_visit_booking,
         supports_full_day_booking,
         search_text,
         moderation_status,
         created_at,
         updated_at
       )
       VALUES (
         $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,'approved',NOW(),NOW()
       )
       RETURNING id`,
      [
        Number(provider.id),
        dto.mainCategoryId,
        dto.subcategoryId,
        dto.name,
        dto.description || null,
        dto.executionMode || 'both',
        dto.requiresSchedule !== false,
        dto.requiresProviderApproval !== false,
        dto.estimatedDurationMinutes == null ? null : Number(dto.estimatedDurationMinutes),
        dto.hasFixedPrice === true,
        dto.startsFromPrice == null ? null : Number(dto.startsFromPrice),
        dto.inspectionRequired === true,
        dto.customQuoteOnly === true,
        dto.workersCount == null ? null : Number(dto.workersCount),
        dto.includesText || null,
        dto.excludesText || null,
        dto.materialsText || null,
        dto.notes || null,
        dto.supportsHourlyBooking === true,
        dto.supportsDailyBooking === true,
        dto.supportsVisitBooking !== false,
        dto.supportsFullDayBooking === true,
        dto.searchText || dto.name,
      ]
    );
    const offeringId = Number(r.rows[0].id);
    let order = 0;
    for (const url of mediaUrls) {
      if (!url) continue;
      await client.query(
        `INSERT INTO service_offering_media (offering_id, media_url, media_kind, sort_order)
         VALUES ($1,$2,'image',$3)`,
        [offeringId, url, order]
      );
      order += 1;
    }
    await replacePricingOptions(client, offeringId, dto.pricingOptions || []);
    await client.query('COMMIT');
    return await getOfferingForProvider(client, provider.id, offeringId);
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function updateOfferingForProvider({
  userId,
  offeringId,
  dto,
  mediaUrls = [],
}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const provider = await getProviderByUserId(client, userId);
    if (!provider) {
      await client.query('ROLLBACK');
      return null;
    }
    const oid = toInt(offeringId);
    if (!oid) {
      await client.query('ROLLBACK');
      return null;
    }
    const existsR = await client.query(
      `SELECT id, moderation_status
       FROM service_offerings
       WHERE id = $1
         AND provider_id = $2
       LIMIT 1`,
      [oid, Number(provider.id)]
    );
    const existingOffering = existsR.rows[0] || null;
    if (!existingOffering) {
      await client.query('ROLLBACK');
      return null;
    }
    await client.query(
      `UPDATE service_offerings
       SET
         main_category_id = COALESCE($3, main_category_id),
         subcategory_id = COALESCE($4, subcategory_id),
         name = COALESCE($5, name),
         description = CASE WHEN $6::text IS NULL THEN description ELSE $6 END,
         execution_mode = COALESCE($7, execution_mode),
         requires_schedule = COALESCE($8, requires_schedule),
         requires_provider_approval = COALESCE($9, requires_provider_approval),
         estimated_duration_minutes = COALESCE($10, estimated_duration_minutes),
         has_fixed_price = COALESCE($11, has_fixed_price),
         starts_from_price = COALESCE($12, starts_from_price),
         inspection_required = COALESCE($13, inspection_required),
         custom_quote_only = COALESCE($14, custom_quote_only),
         workers_count = COALESCE($15, workers_count),
         includes_text = CASE WHEN $16::text IS NULL THEN includes_text ELSE $16 END,
         excludes_text = CASE WHEN $17::text IS NULL THEN excludes_text ELSE $17 END,
         materials_text = CASE WHEN $18::text IS NULL THEN materials_text ELSE $18 END,
         notes = CASE WHEN $19::text IS NULL THEN notes ELSE $19 END,
         supports_hourly_booking = COALESCE($20, supports_hourly_booking),
         supports_daily_booking = COALESCE($21, supports_daily_booking),
          supports_visit_booking = COALESCE($22, supports_visit_booking),
          supports_full_day_booking = COALESCE($23, supports_full_day_booking),
          search_text = COALESCE($24, search_text),
          moderation_status = 'approved',
          updated_at = NOW()
        WHERE id = $1
          AND provider_id = $2`,
      [
        oid,
        Number(provider.id),
        dto.mainCategoryId || null,
        dto.subcategoryId || null,
        dto.name || null,
        dto.description,
        dto.executionMode || null,
        dto.requiresSchedule,
        dto.requiresProviderApproval,
        dto.estimatedDurationMinutes == null ? null : Number(dto.estimatedDurationMinutes),
        dto.hasFixedPrice,
        dto.startsFromPrice == null ? null : Number(dto.startsFromPrice),
        dto.inspectionRequired,
        dto.customQuoteOnly,
        dto.workersCount == null ? null : Number(dto.workersCount),
        dto.includesText,
        dto.excludesText,
        dto.materialsText,
        dto.notes,
        dto.supportsHourlyBooking,
        dto.supportsDailyBooking,
        dto.supportsVisitBooking,
        dto.supportsFullDayBooking,
        dto.searchText || dto.name || null,
      ]
    );

    if (Array.isArray(dto.pricingOptions) && dto.pricingOptions.length > 0) {
      await replacePricingOptions(client, oid, dto.pricingOptions);
    }

    if (Array.isArray(mediaUrls) && mediaUrls.length > 0) {
      await client.query(`DELETE FROM service_offering_media WHERE offering_id = $1`, [
        oid,
      ]);
      let start = 0;
      for (const url of mediaUrls) {
        if (!url) continue;
        await client.query(
          `INSERT INTO service_offering_media (offering_id, media_url, media_kind, sort_order)
           VALUES ($1,$2,'image',$3)`,
          [oid, url, start]
        );
        start += 1;
      }
    }

    await client.query('COMMIT');
    return await getOfferingForProvider(client, provider.id, oid);
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function replacePricingForOffering({ userId, offeringId, pricingOptions = [] }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const provider = await getProviderByUserId(client, userId);
    if (!provider) {
      await client.query('ROLLBACK');
      return null;
    }
    const oid = toInt(offeringId);
    if (!oid) {
      await client.query('ROLLBACK');
      return null;
    }
    const existsR = await client.query(
      `SELECT id
       FROM service_offerings
       WHERE id = $1
         AND provider_id = $2
       LIMIT 1`,
      [oid, provider.id]
    );
    if (!existsR.rows[0]) {
      await client.query('ROLLBACK');
      return null;
    }
    await replacePricingOptions(client, oid, pricingOptions);
    await client.query('COMMIT');
    return await getOfferingForProvider(client, provider.id, oid);
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function createPromotionForProvider({ userId, dto }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const provider = await getProviderByUserId(client, userId);
    if (!provider) {
      await client.query('ROLLBACK');
      return null;
    }

    const r = await client.query(
      `INSERT INTO service_promotions (
         provider_id,
         title,
         description,
         discount_type,
         discount_value,
         special_price,
         starts_at,
         ends_at,
         badge_color,
         is_active,
         created_at,
         updated_at
       )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,TRUE,NOW(),NOW())
       RETURNING *`,
      [
        provider.id,
        dto.title,
        dto.description || null,
        dto.discountType,
        dto.discountValue == null ? null : Number(dto.discountValue),
        dto.specialPrice == null ? null : Number(dto.specialPrice),
        toIsoOrNull(dto.startsAt),
        toIsoOrNull(dto.endsAt),
        dto.badgeColor || null,
      ]
    );
    const promotion = r.rows[0];
    const offeringIds = Array.isArray(dto.offeringIds)
      ? dto.offeringIds.map((x) => Number(x)).filter((x) => x > 0)
      : [];
    for (const offeringId of offeringIds) {
      await client.query(
        `INSERT INTO service_promotion_targets (promotion_id, offering_id)
         SELECT $1, o.id
         FROM service_offerings o
         WHERE o.id = $2
           AND o.provider_id = $3
         ON CONFLICT (promotion_id, offering_id) DO NOTHING`,
        [Number(promotion.id), offeringId, provider.id]
      );
    }
    await client.query('COMMIT');
    return {
      id: Number(promotion.id),
      providerId: Number(promotion.provider_id),
      title: promotion.title,
      description: promotion.description || null,
      discountType: promotion.discount_type,
      discountValue:
        promotion.discount_value == null ? null : Number(promotion.discount_value),
      specialPrice:
        promotion.special_price == null ? null : Number(promotion.special_price),
      startsAt: promotion.starts_at || null,
      endsAt: promotion.ends_at || null,
      badgeColor: promotion.badge_color || null,
      isActive: promotion.is_active === true,
    };
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function createPortfolioItemForProvider({ userId, dto, mediaUrl }) {
  const client = await pool.connect();
  try {
    const provider = await getProviderByUserId(client, userId);
    if (!provider) return null;
    const r = await client.query(
      `INSERT INTO service_portfolio_items (
         provider_id,
         offering_id,
         title,
         description,
         media_url,
         media_kind,
         before_media_url,
         after_media_url,
         sort_order,
         is_pinned,
         created_at,
         updated_at
       )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,NOW(),NOW())
       RETURNING *`,
      [
        provider.id,
        dto.offeringId || null,
        dto.title || null,
        dto.description || null,
        mediaUrl,
        dto.mediaKind || 'image',
        dto.beforeMediaUrl || null,
        dto.afterMediaUrl || null,
        dto.sortOrder == null ? 0 : Number(dto.sortOrder),
        dto.isPinned === true,
      ]
    );
    const row = r.rows[0];
    return {
      id: Number(row.id),
      providerId: Number(row.provider_id),
      offeringId: row.offering_id == null ? null : Number(row.offering_id),
      title: row.title || null,
      description: row.description || null,
      mediaUrl: row.media_url,
      mediaKind: row.media_kind || 'image',
      beforeMediaUrl: row.before_media_url || null,
      afterMediaUrl: row.after_media_url || null,
      sortOrder: Number(row.sort_order || 0),
      isPinned: row.is_pinned === true,
      createdAt: row.created_at || null,
    };
  } finally {
    client.release();
  }
}

export async function deletePortfolioItemForProvider({ userId, portfolioId }) {
  const client = await pool.connect();
  try {
    const provider = await getProviderByUserId(client, userId);
    if (!provider) return false;
    const r = await client.query(
      `DELETE FROM service_portfolio_items
       WHERE id = $1
         AND provider_id = $2`,
      [Number(portfolioId), provider.id]
    );
    return r.rowCount > 0;
  } finally {
    client.release();
  }
}

async function writeRequestHistory(
  client,
  {
    requestId,
    previousStatus = null,
    nextStatus,
    changedByUserId = null,
    note = null,
    bookingVersion = null,
    idempotencyKey = null,
    priceVersion = null,
    bookingSnapshotJson = null,
  }
) {
  await client.query(
    `INSERT INTO service_request_status_history (
       request_id,
       previous_status,
       next_status,
       changed_by_user_id,
       note,
       booking_version,
       idempotency_key,
       price_version,
       booking_snapshot_json
     )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
    [
      Number(requestId),
      previousStatus || null,
      nextStatus,
      changedByUserId == null ? null : Number(changedByUserId),
      note || null,
      bookingVersion == null ? null : Number(bookingVersion),
      idempotencyKey || null,
      priceVersion || null,
      bookingSnapshotJson && typeof bookingSnapshotJson === 'object'
        ? bookingSnapshotJson
        : {},
    ]
  );
}

async function getRequestRaw(client, requestId) {
  const r = await client.query(
    `SELECT
       sr.*,
       so.name AS offering_name,
       sp.business_name AS provider_business_name,
       au.full_name AS customer_full_name
     FROM service_requests sr
     JOIN service_offerings so ON so.id = sr.offering_id
     JOIN service_provider_profiles sp ON sp.id = sr.provider_id
     JOIN app_user au ON au.id = sr.customer_user_id
     WHERE sr.id = $1
     LIMIT 1`,
    [Number(requestId)]
  );
  return r.rows[0] || null;
}

async function listAttachmentsMap(client, requestIds = []) {
  const ids = requestIds
    .map((id) => Number(id))
    .filter((id) => Number.isInteger(id) && id > 0);
  if (!ids.length) return new Map();
  const r = await client.query(
    `SELECT *
     FROM service_request_attachments
     WHERE request_id = ANY($1::bigint[])
     ORDER BY id ASC`,
    [ids]
  );
  const map = new Map();
  for (const row of r.rows) {
    const requestId = Number(row.request_id);
    const list = map.get(requestId) || [];
    list.push({
      id: Number(row.id),
      requestId,
      mediaUrl: row.media_url,
      mediaKind: row.media_kind || 'image',
      createdAt: row.created_at || null,
    });
    map.set(requestId, list);
  }
  return map;
}

async function listQuotesMap(client, requestIds = []) {
  const ids = requestIds
    .map((id) => Number(id))
    .filter((id) => Number.isInteger(id) && id > 0);
  if (!ids.length) return new Map();
  const r = await client.query(
    `SELECT *
     FROM service_request_quotes
     WHERE request_id = ANY($1::bigint[])
     ORDER BY request_id ASC, round_no DESC, id DESC`,
    [ids]
  );
  const map = new Map();
  for (const row of r.rows) {
    const requestId = Number(row.request_id);
    const list = map.get(requestId) || [];
    list.push(mapQuote(row));
    map.set(requestId, list);
  }
  return map;
}

async function listHistoryMap(client, requestIds = []) {
  const ids = requestIds
    .map((id) => Number(id))
    .filter((id) => Number.isInteger(id) && id > 0);
  if (!ids.length) return new Map();
  const r = await client.query(
    `SELECT *
     FROM service_request_status_history
     WHERE request_id = ANY($1::bigint[])
     ORDER BY request_id ASC, created_at DESC, id DESC`,
    [ids]
  );
  const map = new Map();
  for (const row of r.rows) {
    const requestId = Number(row.request_id);
    const list = map.get(requestId) || [];
    list.push({
      id: Number(row.id),
      requestId,
      previousStatus: row.previous_status || null,
      nextStatus: row.next_status,
      changedByUserId:
        row.changed_by_user_id == null ? null : Number(row.changed_by_user_id),
      note: row.note || null,
      createdAt: row.created_at || null,
    });
    map.set(requestId, list);
  }
  return map;
}

async function hydrateRequests(client, rows = []) {
  const ids = rows.map((x) => Number(x.id));
  const attachmentsMap = await listAttachmentsMap(client, ids);
  const quotesMap = await listQuotesMap(client, ids);
  const historyMap = await listHistoryMap(client, ids);
  return rows.map((row) => ({
    ...mapRequest(row),
    attachments: attachmentsMap.get(Number(row.id)) || [],
    quotes: quotesMap.get(Number(row.id)) || [],
    history: historyMap.get(Number(row.id)) || [],
  }));
}

export async function previewServiceBookingByCustomer({
  customerUserId,
  dto,
}) {
  const client = await pool.connect();
  try {
    const context = await fetchBookingOfferingContext(client, {
      offeringId: dto.offeringId,
      providerId: dto.providerId,
      pricingOptionId: dto.pricingOptionId ?? null,
    });
    if (!context?.offering) return null;
    const provider = context.offering.provider_id
      ? await getProviderById(client, context.offering.provider_id)
      : null;
    const preview = buildServiceBookingPreview({
      offering: {
        id: Number(context.offering.id),
        providerId: Number(context.offering.provider_id),
      },
      pricingOption: context.pricingOption,
      pricingType: dto.pricingType || dto.bookingPricingType || dto.pricingModel,
      quantity: dto.quantity,
      durationMinutes: dto.durationMinutes,
      promotion: context.promotion,
      serviceFeeIqd: dto.serviceFeeIqd || 0,
    });
    return {
      offeringId: Number(context.offering.id),
      providerId: Number(context.offering.provider_id),
      customerUserId: Number(customerUserId),
      providerBusinessName: context.offering.provider_business_name || null,
      providerCity: context.offering.provider_city || null,
      providerArea: context.offering.provider_area || null,
      pricingOptionId:
        context.pricingOption == null ? null : Number(context.pricingOption.id),
      preview,
      provider: provider
        ? {
            id: Number(provider.id),
            userId: Number(provider.userId),
            businessName: provider.businessName || null,
            city: provider.city || null,
            area: provider.area || null,
          }
        : null,
      pricingOption: context.pricingOption
        ? {
            id: Number(context.pricingOption.id),
            pricingModel: context.pricingOption.pricing_model,
            pricingUnit: context.pricingOption.pricing_unit,
            amount:
              context.pricingOption.amount == null
                ? null
                : Number(context.pricingOption.amount),
            inspectionRequired: context.pricingOption.inspection_required === true,
            isDefault: context.pricingOption.is_default === true,
          }
        : null,
      promotion: context.promotion ? mapPromotion(context.promotion) : null,
    };
  } finally {
    client.release();
  }
}

function normalizeRequestedServiceSlot({ requestedDate, requestedTime, durationMinutes }) {
  const date = String(requestedDate || '').trim();
  const time = String(requestedTime || '').trim();
  if (!date || !time) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !/^\d{2}:\d{2}(:\d{2})?$/.test(time)) {
    throw new AppError('SERVICE_BOOKING_INVALID_SLOT', { status: 400 });
  }
  const minutes = Math.max(1, Math.round(Number(durationMinutes || 0) || 60));
  return { date, time, durationMinutes: minutes };
}

async function assertServiceBookingSlotAvailable(client, {
  providerId,
  requestedDate,
  requestedTime,
  durationMinutes,
}) {
  const slot = normalizeRequestedServiceSlot({
    requestedDate,
    requestedTime,
    durationMinutes,
  });
  if (!slot) return;

  await client.query(
    `SELECT pg_advisory_xact_lock(hashtext($1), hashtext($2))`,
    ['service_booking_slot', String(Number(providerId))]
  );

  const conflictR = await client.query(
    `WITH requested_slot AS (
       SELECT
         ($1::date + $2::time) AS starts_at,
         (($1::date + $2::time) + ($3::int * interval '1 minute')) AS ends_at
     )
     SELECT sr.id
     FROM service_requests sr
     CROSS JOIN requested_slot slot
     WHERE sr.provider_id = $4
       AND sr.requested_date IS NOT NULL
       AND sr.requested_time IS NOT NULL
       AND sr.status = ANY($5::text[])
       AND (sr.requested_date::timestamp + sr.requested_time) < slot.ends_at
       AND (
         (sr.requested_date::timestamp + sr.requested_time)
         + (
           GREATEST(
             COALESCE(
               sr.booking_duration_minutes,
               ROUND(COALESCE(sr.duration_hours, 1) * 60)::int,
               60
             ),
             1
           ) * interval '1 minute'
         )
       ) > slot.starts_at
     LIMIT 1`,
    [
      slot.date,
      slot.time,
      slot.durationMinutes,
      Number(providerId),
      SERVICE_BOOKING_SLOT_ACTIVE_STATUSES,
    ]
  );
  if (conflictR.rows[0]) {
    throw new AppError('SERVICE_BOOKING_SLOT_UNAVAILABLE', { status: 409 });
  }
}

async function createServiceBookingByCustomer({
  client,
  customerUserId,
  dto,
  attachments = [],
}) {
  const transition = assertValidServiceBookingTransition(
    dto.expectedVersion ?? 0,
    dto.idempotencyKey
  );
  const context = await fetchBookingOfferingContext(client, {
    offeringId: dto.offeringId,
    providerId: dto.providerId,
    pricingOptionId: dto.pricingOptionId ?? null,
  });
  if (!context?.offering) return null;
  if (
    context.offering.provider_approval_status !== 'approved' ||
    context.offering.provider_is_active !== true ||
    context.offering.provider_is_temporarily_paused === true
  ) {
    throw new AppError('SERVICE_PROVIDER_NOT_AVAILABLE', { status: 409 });
  }

  const currentPreview = buildServiceBookingPreview({
    offering: {
      id: Number(context.offering.id),
      providerId: Number(context.offering.provider_id),
    },
    pricingOption: context.pricingOption,
    pricingType: dto.pricingType || dto.bookingPricingType || dto.pricingModel,
    quantity: dto.quantity,
    durationMinutes: dto.durationMinutes,
    promotion: context.promotion,
    serviceFeeIqd: dto.serviceFeeIqd || 0,
  });

  if (
    dto.expectedPriceVersion &&
    String(dto.expectedPriceVersion).trim() !== String(currentPreview.priceVersion)
  ) {
    throw new AppError('SERVICE_PRICE_CHANGED', {
      status: 409,
      details: { expectedPriceVersion: currentPreview.priceVersion },
    });
  }

  const existing = await fetchExistingBookingByIdempotency(client, {
    customerUserId,
    idempotencyKey: transition.idempotencyKey,
  });
  if (existing) {
    const hydrated = await hydrateRequests(client, [existing]);
    return hydrated[0] || null;
  }

  await assertServiceBookingSlotAvailable(client, {
    providerId: dto.providerId,
    requestedDate: dto.requestedDate,
    requestedTime: dto.requestedTime,
    durationMinutes: currentPreview.durationMinutes,
  });

  const requestCode = `SR-${Date.now().toString(36).toUpperCase().slice(-8)}`;
  const insertR = await client.query(
    `INSERT INTO service_requests (
       request_code,
       customer_user_id,
       provider_id,
       offering_id,
       pricing_option_id,
       status,
       requested_execution_mode,
       requested_date,
       requested_time,
       quantity,
       duration_hours,
       notes,
       address_line,
       city,
       area,
       latitude,
       longitude,
       requires_home_service,
       requires_quote,
       final_price,
       final_currency,
       final_pricing_model,
       final_pricing_unit,
       booking_version,
       booking_flow_kind,
       booking_idempotency_key,
       booking_pricing_type,
       booking_price_version,
       booking_unit_price_iqd,
       booking_quantity,
       booking_duration_minutes,
       booking_subtotal_iqd,
       booking_discount_iqd,
       booking_service_fee_iqd,
       booking_total_iqd,
       booking_promotion_snapshot,
       booking_expires_at,
       booking_transition_note,
       created_at,
       updated_at
     )
      VALUES (
        $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,2,'V2',$24,$25,$26,$27,$28,$29,$30,$31,$32,$33,$34,$35,$36,NOW(),NOW()
      )
     RETURNING *`,
    [
      requestCode,
      Number(customerUserId),
      Number(dto.providerId),
      Number(dto.offeringId),
      dto.pricingOptionId || null,
      'PENDING_PROVIDER_CONFIRMATION',
      dto.requestedExecutionMode || null,
      dto.requestedDate || null,
      dto.requestedTime || null,
      dto.quantity == null ? null : Number(dto.quantity),
      dto.durationHours == null ? null : Number(dto.durationHours),
      dto.notes || null,
      dto.addressLine || null,
      dto.city || null,
      dto.area || null,
      dto.latitude == null ? null : Number(dto.latitude),
      dto.longitude == null ? null : Number(dto.longitude),
      dto.requiresHomeService === true,
      dto.requiresQuote === true,
      currentPreview.totalIqd,
      'IQD',
      String(currentPreview.pricingType).toLowerCase(),
      currentPreview.pricingType === 'HOURLY' ? 'hour' : 'job',
      transition.idempotencyKey,
       currentPreview.pricingType,
       currentPreview.priceVersion,
       currentPreview.unitPriceIqd,
      currentPreview.quantity,
      currentPreview.durationMinutes,
      currentPreview.subtotalIqd,
      currentPreview.discountIqd,
      currentPreview.serviceFeeIqd,
      currentPreview.totalIqd,
       JSON.stringify(currentPreview.promotionSnapshot || {}),
       currentPreview.expiresAt,
       'booking_created',
    ]
  );

  const request = insertR.rows[0];
  for (const item of attachments) {
    await client.query(
      `INSERT INTO service_request_attachments (request_id, media_url, media_kind)
       VALUES ($1,$2,$3)`,
      [Number(request.id), item.mediaUrl, item.mediaKind || 'image']
    );
  }
    await writeRequestHistory(client, {
      requestId: Number(request.id),
      previousStatus: null,
      nextStatus: 'PENDING_PROVIDER_CONFIRMATION',
      changedByUserId: Number(customerUserId),
      note: 'booking_created',
      bookingVersion: 2,
      idempotencyKey: transition.idempotencyKey,
      priceVersion: currentPreview.priceVersion,
      bookingSnapshotJson: currentPreview,
    });

  const row = await getRequestRaw(client, request.id);
  if (!row) return null;
  const hydrated = await hydrateRequests(client, [row]);
  return hydrated[0] || null;
}

async function transitionServiceBookingByProviderUser({
  client,
  userId,
  requestId,
  status,
  note = null,
  scheduledStartAt = null,
  scheduledEndAt = null,
  expectedVersion = null,
  idempotencyKey = null,
}) {
  const transition = assertValidServiceBookingTransition(expectedVersion, idempotencyKey);
  const provider = await getProviderByUserId(client, userId);
  if (!provider) return null;
  const request = await getRequestRaw(client, requestId);
  if (!request || Number(request.provider_id) !== Number(provider.id)) return null;
  const currentStatus = normalizeServiceBookingState(request.status);
  const nextStatus = normalizeServiceBookingState(status);
  const providerAllowed = new Map([
    ['PENDING_PROVIDER_CONFIRMATION', new Set(['CONFIRMED', 'REJECTED_BY_PROVIDER', 'CANCELLED_BY_PROVIDER', 'CANCELLED_BY_ADMIN', 'EXPIRED'])],
    ['CONFIRMED', new Set(['IN_PROGRESS', 'CANCELLED_BY_PROVIDER', 'CANCELLED_BY_ADMIN'])],
    ['IN_PROGRESS', new Set(['PROVIDER_COMPLETED', 'CANCELLED_BY_PROVIDER', 'CANCELLED_BY_ADMIN'])],
    ['PROVIDER_COMPLETED', new Set([])],
  ]);
  const allowed = providerAllowed.get(currentStatus) || new Set();
  if (!allowed.has(nextStatus) && currentStatus !== nextStatus) {
    throw new AppError('SERVICE_BOOKING_INVALID_TRANSITION', { status: 409 });
  }

  const history = await client.query(
    `SELECT id, next_status
     FROM service_request_status_history
     WHERE request_id = $1
       AND idempotency_key = $2
     LIMIT 1`,
    [Number(requestId), transition.idempotencyKey]
  );
  if (history.rows[0]) {
    const hydrated = await hydrateRequests(client, [request]);
    return hydrated[0] || null;
  }

  const expected =
    transition.expectedVersion > 0
      ? Number(transition.expectedVersion)
      : Number(request.booking_version || 0);
  if (Number(request.booking_version || 0) !== expected) {
    throw new AppError('SERVICE_BOOKING_VERSION_CONFLICT', { status: 409 });
  }

  const bookingSnapshot = safeJson(request.booking_promotion_snapshot || {});
  let bookingProviderCompletedAt = request.booking_provider_completed_at || null;
  let bookingFinalizationDueAt = request.booking_finalization_due_at || null;
  let bookingFinalizedAt = request.booking_finalized_at || null;

  if (nextStatus === 'PROVIDER_COMPLETED') {
    bookingProviderCompletedAt = new Date().toISOString();
    bookingFinalizationDueAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  }
  if (nextStatus === 'COMPLETED' || nextStatus === 'DISPUTED') {
    bookingFinalizedAt = new Date().toISOString();
    bookingFinalizationDueAt = null;
  }

  await client.query(
    `UPDATE service_requests
     SET
        status = $2::text,
       booking_version = booking_version + 1,
       booking_idempotency_key = $3,
       booking_transition_note = $4,
       scheduled_start_at = CASE WHEN $5::timestamptz IS NULL THEN scheduled_start_at ELSE $5 END,
       scheduled_end_at = CASE WHEN $6::timestamptz IS NULL THEN scheduled_end_at ELSE $6 END,
        rejected_reason = CASE WHEN $2::text = 'REJECTED_BY_PROVIDER' THEN COALESCE($4, rejected_reason) ELSE rejected_reason END,
        cancel_reason = CASE WHEN $2::text IN ('CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_PROVIDER', 'CANCELLED_BY_ADMIN') THEN COALESCE($4, cancel_reason) ELSE cancel_reason END,
        completed_at = CASE WHEN $2::text = 'COMPLETED' THEN NOW() ELSE completed_at END,
       booking_provider_completed_at = COALESCE($7::timestamptz, booking_provider_completed_at),
       booking_finalization_due_at = COALESCE($8::timestamptz, booking_finalization_due_at),
       booking_finalized_at = COALESCE($9::timestamptz, booking_finalized_at),
       updated_at = NOW()
     WHERE id = $1`,
    [
      Number(requestId),
      nextStatus,
      transition.idempotencyKey,
      note || null,
      scheduledStartAt || null,
      scheduledEndAt || null,
      bookingProviderCompletedAt,
      bookingFinalizationDueAt,
      bookingFinalizedAt,
    ]
  );

  await writeRequestHistory(client, {
    requestId: Number(requestId),
    previousStatus: currentStatus,
    nextStatus,
    changedByUserId: Number(userId),
    note,
    bookingVersion: expected + 1,
    idempotencyKey: transition.idempotencyKey,
    bookingSnapshotJson: {
      ...bookingSnapshot,
      bookingProviderCompletedAt,
      bookingFinalizationDueAt,
      bookingFinalizedAt,
    },
  });

  const row = await getRequestRaw(client, requestId);
  const hydrated = await hydrateRequests(client, [row]);
  return hydrated[0] || null;
}

async function transitionServiceBookingByCustomer({
  client,
  userId,
  requestId,
  status,
  note = null,
  expectedVersion = null,
  idempotencyKey = null,
}) {
  const transition = assertValidServiceBookingTransition(expectedVersion, idempotencyKey);
  const request = await getRequestRaw(client, requestId);
  if (!request || Number(request.customer_user_id) !== Number(userId)) return null;
  const currentStatus = normalizeServiceBookingState(request.status);
  const nextStatus = normalizeServiceBookingState(status);
  const customerAllowed = new Map([
    ['PROVIDER_COMPLETED', new Set(['COMPLETED', 'DISPUTED'])],
    ['PENDING_PROVIDER_CONFIRMATION', new Set(['CANCELLED_BY_CUSTOMER'])],
    ['CONFIRMED', new Set(['CANCELLED_BY_CUSTOMER'])],
    ['IN_PROGRESS', new Set(['CANCELLED_BY_CUSTOMER'])],
  ]);
  const allowed = customerAllowed.get(currentStatus) || new Set();
  if (!allowed.has(nextStatus) && currentStatus !== nextStatus) {
    throw new AppError('SERVICE_BOOKING_INVALID_TRANSITION', { status: 409 });
  }

  const history = await client.query(
    `SELECT id, next_status
     FROM service_request_status_history
     WHERE request_id = $1
       AND idempotency_key = $2
     LIMIT 1`,
    [Number(requestId), transition.idempotencyKey]
  );
  if (history.rows[0]) {
    const hydrated = await hydrateRequests(client, [request]);
    return hydrated[0] || null;
  }

  const expected =
    transition.expectedVersion > 0
      ? Number(transition.expectedVersion)
      : Number(request.booking_version || 0);
  if (Number(request.booking_version || 0) !== expected) {
    throw new AppError('SERVICE_BOOKING_VERSION_CONFLICT', { status: 409 });
  }

  const bookingSnapshot = safeJson(request.booking_promotion_snapshot || {});
  let bookingFinalizedAt = request.booking_finalized_at || null;
  if (nextStatus === 'COMPLETED' || nextStatus === 'DISPUTED') {
    bookingFinalizedAt = new Date().toISOString();
  }

  await client.query(
    `UPDATE service_requests
     SET
        status = $2::text,
       booking_version = booking_version + 1,
       booking_idempotency_key = $3,
       booking_transition_note = $4,
        cancel_reason = CASE WHEN $2::text = 'CANCELLED_BY_CUSTOMER' THEN COALESCE($4, cancel_reason) ELSE cancel_reason END,
        completed_at = CASE WHEN $2::text = 'COMPLETED' THEN NOW() ELSE completed_at END,
       booking_finalized_at = COALESCE($5::timestamptz, booking_finalized_at),
       updated_at = NOW()
     WHERE id = $1`,
    [
      Number(requestId),
      nextStatus,
      transition.idempotencyKey,
      note || null,
      bookingFinalizedAt,
    ]
  );

  await writeRequestHistory(client, {
    requestId: Number(requestId),
    previousStatus: currentStatus,
    nextStatus,
    changedByUserId: Number(userId),
    note,
    bookingVersion: expected + 1,
    idempotencyKey: transition.idempotencyKey,
    bookingSnapshotJson: {
      ...bookingSnapshot,
      bookingFinalizedAt,
    },
  });

  const row = await getRequestRaw(client, requestId);
  const hydrated = await hydrateRequests(client, [row]);
  return hydrated[0] || null;
}

export async function createServiceRequestByCustomer({
  customerUserId,
  dto,
  attachments = [],
}) {
  await ensureServiceBookingSchema();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (isV2BookingRequest(dto)) {
      const created = await createServiceBookingByCustomer({
        client,
        customerUserId,
        dto,
        attachments,
      });
      await client.query('COMMIT');
      return created;
    }

    const offeringR = await client.query(
      `SELECT o.id, o.provider_id, o.custom_quote_only, o.inspection_required
       FROM service_offerings o
       WHERE o.id = $1
         AND o.provider_id = $2
       LIMIT 1`,
      [Number(dto.offeringId), Number(dto.providerId)]
    );
    const offering = offeringR.rows[0] || null;
    if (!offering) {
      await client.query('ROLLBACK');
      return null;
    }
    const requiresQuote =
      dto.requiresQuote === true ||
      offering.custom_quote_only === true ||
      offering.inspection_required === true;
    const requestCode = `SR-${Date.now().toString(36).toUpperCase().slice(-8)}`;
    const status = requiresQuote ? 'awaiting_provider' : 'pending';
    const insertR = await client.query(
      `INSERT INTO service_requests (
         request_code,
         customer_user_id,
         provider_id,
         offering_id,
         pricing_option_id,
         status,
         requested_execution_mode,
         requested_date,
         requested_time,
         quantity,
         duration_hours,
         notes,
         address_line,
         city,
         area,
         latitude,
         longitude,
         requires_home_service,
         requires_quote,
         booking_version,
         booking_flow_kind,
         created_at,
         updated_at
       )
       VALUES (
         $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,1,'LEGACY',NOW(),NOW()
       )
       RETURNING *`,
      [
        requestCode,
        Number(customerUserId),
        Number(dto.providerId),
        Number(dto.offeringId),
        dto.pricingOptionId || null,
        status,
        dto.requestedExecutionMode || null,
        dto.requestedDate || null,
        dto.requestedTime || null,
        dto.quantity == null ? null : Number(dto.quantity),
        dto.durationHours == null ? null : Number(dto.durationHours),
        dto.notes || null,
        dto.addressLine || null,
        dto.city || null,
        dto.area || null,
        dto.latitude == null ? null : Number(dto.latitude),
        dto.longitude == null ? null : Number(dto.longitude),
        dto.requiresHomeService === true,
        requiresQuote,
      ]
    );
    const request = insertR.rows[0];
    for (const item of attachments) {
      await client.query(
        `INSERT INTO service_request_attachments (request_id, media_url, media_kind)
         VALUES ($1,$2,$3)`,
        [Number(request.id), item.mediaUrl, item.mediaKind || 'image']
      );
    }
    await writeRequestHistory(client, {
      requestId: Number(request.id),
      previousStatus: null,
      nextStatus: status,
      changedByUserId: Number(customerUserId),
      note: 'request_created',
      bookingVersion: 1,
    });
    await client.query('COMMIT');
    const row = await getRequestRaw(client, request.id);
    if (!row) return null;
    const hydrated = await hydrateRequests(client, [row]);
    return hydrated[0] || null;
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function listCustomerRequests({ userId, query = {} }) {
  const client = await pool.connect();
  try {
    const params = [Number(userId)];
    const filters = [`sr.customer_user_id = $1`];
    if (query.status) {
      params.push(query.status);
      filters.push(`sr.status = $${params.length}`);
    }
    params.push(Math.max(1, Math.min(100, Number(query.limit) || 20)));
    params.push(Math.max(0, Number(query.offset) || 0));
    const r = await client.query(
      `SELECT
         sr.*,
         so.name AS offering_name,
         sp.business_name AS provider_business_name,
         au.full_name AS customer_full_name
       FROM service_requests sr
       JOIN service_offerings so ON so.id = sr.offering_id
       JOIN service_provider_profiles sp ON sp.id = sr.provider_id
       JOIN app_user au ON au.id = sr.customer_user_id
       WHERE ${filters.join(' AND ')}
       ORDER BY sr.created_at DESC, sr.id DESC
       LIMIT $${params.length - 1}
       OFFSET $${params.length}`,
      params
    );
    return await hydrateRequests(client, r.rows);
  } finally {
    client.release();
  }
}

export async function listProviderRequestsByUser({ userId, query = {} }) {
  const client = await pool.connect();
  try {
    const provider = await getProviderByUserId(client, userId);
    if (!provider) return [];
    const params = [Number(provider.id)];
    const filters = [`sr.provider_id = $1`];
    if (query.status) {
      params.push(query.status);
      filters.push(`sr.status = $${params.length}`);
    }
    params.push(Math.max(1, Math.min(100, Number(query.limit) || 20)));
    params.push(Math.max(0, Number(query.offset) || 0));
    const r = await client.query(
      `SELECT
         sr.*,
         so.name AS offering_name,
         sp.business_name AS provider_business_name,
         au.full_name AS customer_full_name
       FROM service_requests sr
       JOIN service_offerings so ON so.id = sr.offering_id
       JOIN service_provider_profiles sp ON sp.id = sr.provider_id
       JOIN app_user au ON au.id = sr.customer_user_id
       WHERE ${filters.join(' AND ')}
       ORDER BY sr.created_at DESC, sr.id DESC
       LIMIT $${params.length - 1}
       OFFSET $${params.length}`,
      params
    );
    return await hydrateRequests(client, r.rows);
  } finally {
    client.release();
  }
}

export async function getServiceRequestForUser({ userId, requestId }) {
  const client = await pool.connect();
  try {
    const row = await getRequestRaw(client, requestId);
    if (!row) return null;
    const provider = await getProviderById(client, row.provider_id);
    const isCustomer = Number(row.customer_user_id) === Number(userId);
    const isProviderOwner = provider && Number(provider.userId) === Number(userId);
    if (!isCustomer && !isProviderOwner) return null;
    const hydrated = await hydrateRequests(client, [row]);
    return hydrated[0] || null;
  } finally {
    client.release();
  }
}

export async function createQuoteForRequest({ userId, requestId, dto }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const provider = await getProviderByUserId(client, userId);
    if (!provider) {
      await client.query('ROLLBACK');
      return null;
    }
    const request = await getRequestRaw(client, requestId);
    if (!request || Number(request.provider_id) !== Number(provider.id)) {
      await client.query('ROLLBACK');
      return null;
    }
    const roundR = await client.query(
      `SELECT COALESCE(MAX(round_no), 0) + 1 AS next_round
       FROM service_request_quotes
       WHERE request_id = $1`,
      [Number(requestId)]
    );
    const roundNo = Number(roundR.rows[0]?.next_round || 1);
    const insertR = await client.query(
      `INSERT INTO service_request_quotes (
         request_id,
         provider_id,
         quoted_by_user_id,
         round_no,
         quote_status,
         pricing_model,
         pricing_unit,
         amount,
         min_amount,
         max_amount,
         visit_fee,
         currency,
         inspection_required,
         proposed_visit_at,
         proposed_start_at,
         proposed_end_at,
         note,
         expires_at,
         created_at,
         updated_at
       )
       VALUES (
         $1,$2,$3,$4,'pending_customer',$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,NOW(),NOW()
       )
       RETURNING *`,
      [
        Number(requestId),
        Number(provider.id),
        Number(userId),
        roundNo,
        dto.pricingModel,
        dto.pricingUnit,
        toNum(dto.amount),
        toNum(dto.minAmount),
        toNum(dto.maxAmount),
        toNum(dto.visitFee),
        dto.currency || 'IQD',
        dto.inspectionRequired === true,
        toIsoOrNull(dto.proposedVisitAt),
        toIsoOrNull(dto.proposedStartAt),
        toIsoOrNull(dto.proposedEndAt),
        dto.note || null,
        toIsoOrNull(dto.expiresAt),
      ]
    );
    await client.query(
      `UPDATE service_requests
       SET status = 'awaiting_provider', updated_at = NOW()
       WHERE id = $1`,
      [Number(requestId)]
    );
    await writeRequestHistory(client, {
      requestId: Number(requestId),
      previousStatus: request.status,
      nextStatus: 'awaiting_provider',
      changedByUserId: Number(userId),
      note: `quote_round_${roundNo}`,
    });
    await client.query('COMMIT');
    return mapQuote(insertR.rows[0]);
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function respondToQuoteByCustomer({
  userId,
  requestId,
  quoteId,
  action,
  note = null,
}) {
  await ensureServiceBookingSchema();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const request = await getRequestRaw(client, requestId);
    if (!request || Number(request.customer_user_id) !== Number(userId)) {
      await client.query('ROLLBACK');
      return null;
    }
    const quoteR = await client.query(
      `SELECT *
       FROM service_request_quotes
       WHERE id = $1
         AND request_id = $2
       LIMIT 1`,
      [Number(quoteId), Number(requestId)]
    );
    const quote = quoteR.rows[0] || null;
    if (!quote) {
      await client.query('ROLLBACK');
      return null;
    }
    const quoteStatus = action === 'accepted' ? 'accepted' : 'rejected';
    const targetRequestStatus = action === 'accepted' ? 'accepted' : 'awaiting_provider';
    if (
      String(quote.quote_status || '').trim() === quoteStatus &&
      String(request.status || '').trim() === targetRequestStatus
    ) {
      await client.query('COMMIT');
      const row = await getRequestRaw(client, requestId);
      if (!row) return null;
      const hydrated = await hydrateRequests(client, [row]);
      return hydrated[0] || null;
    }
    await client.query(
      `UPDATE service_request_quotes
       SET
         quote_status = $3,
         responded_at = NOW(),
         responded_by_user_id = $4,
         note = COALESCE($5, note),
         updated_at = NOW()
       WHERE id = $1
         AND request_id = $2`,
      [Number(quoteId), Number(requestId), quoteStatus, Number(userId), note || null]
    );
    const nextBookingVersion = Number(request.booking_version || 0) + 1;
    if (action === 'accepted') {
      await client.query(
        `UPDATE service_requests
         SET
           accepted_quote_id = $2,
           final_price = COALESCE($3, final_price),
           final_currency = COALESCE($4, final_currency),
           final_pricing_model = COALESCE($5, final_pricing_model),
           final_pricing_unit = COALESCE($6, final_pricing_unit),
           booking_version = COALESCE(booking_version, 0) + 1,
           status = 'accepted',
           updated_at = NOW()
         WHERE id = $1`,
        [
          Number(requestId),
          Number(quoteId),
          quote.amount == null ? null : Number(quote.amount),
          quote.currency || null,
          quote.pricing_model || null,
          quote.pricing_unit || null,
        ]
      );
      await writeRequestHistory(client, {
        requestId: Number(requestId),
        previousStatus: request.status,
        nextStatus: 'accepted',
        changedByUserId: Number(userId),
        note: 'quote_accepted',
        bookingVersion: nextBookingVersion,
      });
    } else {
      await client.query(
        `UPDATE service_requests
         SET
           booking_version = COALESCE(booking_version, 0) + 1,
           status = 'awaiting_provider',
           updated_at = NOW()
         WHERE id = $1`,
        [Number(requestId)]
      );
      await writeRequestHistory(client, {
        requestId: Number(requestId),
        previousStatus: request.status,
        nextStatus: 'awaiting_provider',
        changedByUserId: Number(userId),
        note: 'quote_rejected',
        bookingVersion: nextBookingVersion,
      });
    }
    await client.query('COMMIT');
    const row = await getRequestRaw(client, requestId);
    if (!row) return null;
    const hydrated = await hydrateRequests(client, [row]);
    return hydrated[0] || null;
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function updateRequestStatusByProviderUser({
  userId,
  requestId,
  status,
  note = null,
  scheduledStartAt = null,
  scheduledEndAt = null,
  expectedVersion = null,
  idempotencyKey = null,
  dto = null,
}) {
  await ensureServiceBookingSchema();
  const resolvedStatus = status ?? dto?.status ?? dto?.bookingStatus ?? null;
  const resolvedNote = note ?? dto?.note ?? null;
  const resolvedScheduledStartAt =
    scheduledStartAt ?? dto?.scheduledStartAt ?? dto?.scheduled_start_at ?? null;
  const resolvedScheduledEndAt =
    scheduledEndAt ?? dto?.scheduledEndAt ?? dto?.scheduled_end_at ?? null;
  const resolvedExpectedVersion =
    expectedVersion ?? dto?.expectedVersion ?? dto?.bookingVersion ?? null;
  const resolvedIdempotencyKey =
    idempotencyKey ??
    dto?.idempotencyKey ??
    dto?.bookingIdempotencyKey ??
    (normalizeServiceBookingState(resolvedStatus)
      ? `legacy-service-booking:${Number(requestId)}:${String(resolvedStatus).trim()}:${resolvedExpectedVersion ?? 'na'}`
      : null);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const provider = await getProviderByUserId(client, userId);
    const request = await getRequestRaw(client, requestId);
    if (!provider || !request || Number(request.provider_id) !== Number(provider.id)) {
      await client.query('ROLLBACK');
      return null;
    }
    const bookingStatus = normalizeServiceBookingState(resolvedStatus);
    const shouldUseBookingFlow = Boolean(bookingStatus) && isDirectBookingV2(request);
    if (shouldUseBookingFlow) {
      const updated = await transitionServiceBookingByProviderUser({
        client,
        userId,
        requestId,
        status: bookingStatus,
        note: resolvedNote,
        scheduledStartAt: resolvedScheduledStartAt,
        scheduledEndAt: resolvedScheduledEndAt,
        expectedVersion: resolvedExpectedVersion,
        idempotencyKey: resolvedIdempotencyKey,
      });
      if (!updated) {
        await client.query('ROLLBACK');
        return null;
      }
      await client.query('COMMIT');
      return updated;
    }
    if (resolvedIdempotencyKey) {
      const legacyHistory = await client.query(
        `SELECT id
         FROM service_request_status_history
         WHERE request_id = $1
           AND idempotency_key = $2
         LIMIT 1`,
        [Number(requestId), resolvedIdempotencyKey]
      );
      if (legacyHistory.rows[0]) {
        await client.query('COMMIT');
        const row = await getRequestRaw(client, requestId);
        if (!row) return null;
        const hydrated = await hydrateRequests(client, [row]);
        return hydrated[0] || null;
      }
    }
    const nextBookingVersion = Number(request.booking_version || 0) + 1;
    await client.query(
      `UPDATE service_requests
       SET
         status = $2::text,
         booking_version = COALESCE(booking_version, 0) + 1,
         booking_idempotency_key = COALESCE($6, booking_idempotency_key),
         booking_transition_note = COALESCE($5, booking_transition_note),
         scheduled_start_at = CASE WHEN $3::timestamptz IS NULL THEN scheduled_start_at ELSE $3 END,
         scheduled_end_at = CASE WHEN $4::timestamptz IS NULL THEN scheduled_end_at ELSE $4 END,
         rejected_reason = CASE WHEN $2::text = 'rejected' THEN COALESCE($5, rejected_reason) ELSE rejected_reason END,
         cancel_reason = CASE WHEN $2::text = 'cancelled' THEN COALESCE($5, cancel_reason) ELSE cancel_reason END,
         completed_at = CASE WHEN $2::text = 'completed' THEN NOW() ELSE completed_at END,
        updated_at = NOW()
      WHERE id = $1`,
      [
        Number(requestId),
        resolvedStatus,
        toIsoOrNull(resolvedScheduledStartAt),
        toIsoOrNull(resolvedScheduledEndAt),
        resolvedNote || null,
        resolvedIdempotencyKey || null,
      ]
    );
    await writeRequestHistory(client, {
      requestId: Number(requestId),
      previousStatus: request.status,
      nextStatus: resolvedStatus,
      changedByUserId: Number(userId),
      note: resolvedNote,
      bookingVersion: nextBookingVersion,
      idempotencyKey: resolvedIdempotencyKey,
    });
    await client.query('COMMIT');
    const row = await getRequestRaw(client, requestId);
    if (!row) return null;
    const hydrated = await hydrateRequests(client, [row]);
    return hydrated[0] || null;
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function updateRequestStatusByCustomer({
  userId,
  requestId,
  status,
  note = null,
  expectedVersion = null,
  idempotencyKey = null,
  dto = null,
}) {
  await ensureServiceBookingSchema();
  const resolvedStatus = status ?? dto?.status ?? dto?.bookingStatus ?? null;
  const resolvedNote = note ?? dto?.note ?? null;
  const resolvedExpectedVersion =
    expectedVersion ?? dto?.expectedVersion ?? dto?.bookingVersion ?? null;
  const resolvedIdempotencyKey =
    idempotencyKey ??
    dto?.idempotencyKey ??
    dto?.bookingIdempotencyKey ??
    (normalizeServiceBookingState(resolvedStatus)
      ? `legacy-service-booking:${Number(requestId)}:${String(resolvedStatus).trim()}:${resolvedExpectedVersion ?? 'na'}`
      : null);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const request = await getRequestRaw(client, requestId);
    if (!request || Number(request.customer_user_id) !== Number(userId)) {
      await client.query('ROLLBACK');
      return null;
    }
    const bookingStatus = normalizeServiceBookingState(resolvedStatus);
    const shouldUseBookingFlow = Boolean(bookingStatus) && isDirectBookingV2(request);
    if (shouldUseBookingFlow) {
      const updated = await transitionServiceBookingByCustomer({
        client,
        userId,
        requestId,
        status: bookingStatus,
        note: resolvedNote,
        expectedVersion: resolvedExpectedVersion,
        idempotencyKey: resolvedIdempotencyKey,
      });
      if (!updated) {
        await client.query('ROLLBACK');
        return null;
      }
      await client.query('COMMIT');
      return updated;
    }
    if (resolvedIdempotencyKey) {
      const legacyHistory = await client.query(
        `SELECT id
         FROM service_request_status_history
         WHERE request_id = $1
           AND idempotency_key = $2
         LIMIT 1`,
        [Number(requestId), resolvedIdempotencyKey]
      );
      if (legacyHistory.rows[0]) {
        await client.query('COMMIT');
        const row = await getRequestRaw(client, requestId);
        if (!row) return null;
        const hydrated = await hydrateRequests(client, [row]);
        return hydrated[0] || null;
      }
    }
    const nextBookingVersion = Number(request.booking_version || 0) + 1;
    await client.query(
      `UPDATE service_requests
       SET
         status = $2::text,
         booking_version = COALESCE(booking_version, 0) + 1,
         booking_idempotency_key = COALESCE($5, booking_idempotency_key),
         booking_transition_note = COALESCE($4, booking_transition_note),
         cancelled_by_user_id = CASE WHEN $2::text = 'cancelled' THEN $3 ELSE cancelled_by_user_id END,
         cancel_reason = CASE WHEN $2::text = 'cancelled' THEN COALESCE($4, cancel_reason) ELSE cancel_reason END,
         updated_at = NOW()
      WHERE id = $1`,
      [Number(requestId), resolvedStatus, Number(userId), resolvedNote || null, resolvedIdempotencyKey || null]
    );
    await writeRequestHistory(client, {
      requestId: Number(requestId),
      previousStatus: request.status,
      nextStatus: resolvedStatus,
      changedByUserId: Number(userId),
      note: resolvedNote,
      bookingVersion: nextBookingVersion,
      idempotencyKey: resolvedIdempotencyKey,
    });
    await client.query('COMMIT');
    const row = await getRequestRaw(client, requestId);
    if (!row) return null;
    const hydrated = await hydrateRequests(client, [row]);
    return hydrated[0] || null;
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function createReviewByCustomer({ userId, dto }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const request = await getRequestRaw(client, dto.requestId);
    if (!request || Number(request.customer_user_id) !== Number(userId)) {
      await client.query('ROLLBACK');
      return { error: 'REQUEST_NOT_FOUND' };
    }
    if (String(request.status) !== 'completed') {
      await client.query('ROLLBACK');
      return { error: 'REQUEST_NOT_COMPLETED' };
    }
    const existingR = await client.query(
      `SELECT id
       FROM service_reviews
       WHERE request_id = $1
       LIMIT 1`,
      [Number(dto.requestId)]
    );
    if (existingR.rows[0]) {
      await client.query('ROLLBACK');
      return { error: 'REVIEW_ALREADY_EXISTS' };
    }
    const insertR = await client.query(
      `INSERT INTO service_reviews (
         request_id,
         offering_id,
         provider_id,
         customer_user_id,
         rating,
         comment,
         service_as_described,
         on_time,
         price_fair,
         recommend,
         image_urls_json,
         created_at,
         updated_at
       )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb,NOW(),NOW())
       RETURNING *`,
      [
        Number(dto.requestId),
        Number(request.offering_id),
        Number(request.provider_id),
        Number(userId),
        Number(dto.rating),
        dto.comment || null,
        dto.serviceAsDescribed,
        dto.onTime,
        dto.priceFair,
        dto.recommend,
        JSON.stringify(Array.isArray(dto.imageUrls) ? dto.imageUrls : []),
      ]
    );

    await client.query(
      `UPDATE service_provider_profiles p
       SET
         rating_avg = COALESCE(x.avg_rating, 0),
         rating_count = COALESCE(x.rating_count, 0),
         updated_at = NOW()
       FROM (
         SELECT provider_id, AVG(rating)::numeric(3,2) AS avg_rating, COUNT(*)::int AS rating_count
         FROM service_reviews
         WHERE provider_id = $1
         GROUP BY provider_id
       ) x
       WHERE p.id = $1
         AND p.id = x.provider_id`,
      [Number(request.provider_id)]
    );

    await client.query(
      `UPDATE service_offerings o
       SET
         rating_avg = COALESCE(x.avg_rating, 0),
         rating_count = COALESCE(x.rating_count, 0),
         updated_at = NOW()
       FROM (
         SELECT offering_id, AVG(rating)::numeric(3,2) AS avg_rating, COUNT(*)::int AS rating_count
         FROM service_reviews
         WHERE offering_id = $1
         GROUP BY offering_id
       ) x
       WHERE o.id = $1
         AND o.id = x.offering_id`,
      [Number(request.offering_id)]
    );

    await client.query('COMMIT');
    return mapReview(insertR.rows[0]);
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function listProviderReviews(providerId, { limit = 40, offset = 0 } = {}) {
  const pid = toInt(providerId);
  if (!pid) return [];
  const r = await q(
    `SELECT
       r.*,
       u.full_name AS customer_full_name,
       u.image_url AS customer_image_url
     FROM service_reviews r
     JOIN app_user u ON u.id = r.customer_user_id
     WHERE r.provider_id = $1
     ORDER BY r.created_at DESC
     LIMIT $2 OFFSET $3`,
    [pid, Math.max(1, Math.min(100, Number(limit) || 40)), Math.max(0, Number(offset) || 0)]
  );
  return r.rows.map(mapReview);
}

export async function listOfferingReviews(offeringId, { limit = 40, offset = 0 } = {}) {
  const oid = toInt(offeringId);
  if (!oid) return [];
  const r = await q(
    `SELECT
       r.*,
       u.full_name AS customer_full_name,
       u.image_url AS customer_image_url
     FROM service_reviews r
     JOIN app_user u ON u.id = r.customer_user_id
     WHERE r.offering_id = $1
     ORDER BY r.created_at DESC
     LIMIT $2 OFFSET $3`,
    [oid, Math.max(1, Math.min(100, Number(limit) || 40)), Math.max(0, Number(offset) || 0)]
  );
  return r.rows.map(mapReview);
}

export async function createCategorySuggestion({ userId, dto }) {
  const r = await q(
    `INSERT INTO service_category_suggestions (
       suggested_by_user_id,
       parent_category_id,
       suggestion_type,
       name,
       details,
       status,
       created_at,
       updated_at
     )
     VALUES ($1,$2,$3,$4,$5,'pending',NOW(),NOW())
     RETURNING *`,
    [Number(userId), dto.parentCategoryId || null, dto.suggestionType, dto.name, dto.details || null]
  );
  const row = r.rows[0] || null;
  if (!row) return null;
  return {
    id: Number(row.id),
    suggestedByUserId: Number(row.suggested_by_user_id),
    parentCategoryId: row.parent_category_id == null ? null : Number(row.parent_category_id),
    suggestionType: row.suggestion_type,
    name: row.name,
    details: row.details || null,
    status: row.status,
    mergeTargetCategoryId:
      row.merge_target_category_id == null ? null : Number(row.merge_target_category_id),
    reviewedByUserId:
      row.reviewed_by_user_id == null ? null : Number(row.reviewed_by_user_id),
    reviewedAt: row.reviewed_at || null,
    reviewNote: row.review_note || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

export async function listMyCategorySuggestions(userId, { limit = 40, offset = 0 } = {}) {
  const r = await q(
    `SELECT *
     FROM service_category_suggestions
     WHERE suggested_by_user_id = $1
     ORDER BY created_at DESC
     LIMIT $2 OFFSET $3`,
    [
      Number(userId),
      Math.max(1, Math.min(100, Number(limit) || 40)),
      Math.max(0, Number(offset) || 0),
    ]
  );
  return r.rows.map((row) => ({
    id: Number(row.id),
    suggestedByUserId: Number(row.suggested_by_user_id),
    parentCategoryId: row.parent_category_id == null ? null : Number(row.parent_category_id),
    suggestionType: row.suggestion_type,
    name: row.name,
    details: row.details || null,
    status: row.status,
    mergeTargetCategoryId:
      row.merge_target_category_id == null ? null : Number(row.merge_target_category_id),
    reviewedByUserId:
      row.reviewed_by_user_id == null ? null : Number(row.reviewed_by_user_id),
    reviewedAt: row.reviewed_at || null,
    reviewNote: row.review_note || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  }));
}

export async function listProviderWorkspace(userId) {
  const client = await pool.connect();
  try {
    const provider = await getProviderByUserId(client, userId);
    if (!provider) return null;
    const areasR = await client.query(
      `SELECT city, area, note
       FROM service_provider_areas
       WHERE provider_id = $1
       ORDER BY city ASC, area ASC NULLS LAST`,
      [provider.id]
    );
    const availabilityR = await client.query(
      `SELECT day_of_week, start_time, end_time, is_active
       FROM service_provider_availability_rules
       WHERE provider_id = $1
       ORDER BY day_of_week ASC, start_time ASC`,
      [provider.id]
    );
    const offeringsR = await client.query(
      `SELECT
         o.*,
         mc.name AS main_category_name,
         sc.name AS subcategory_name,
         p.business_name AS provider_business_name,
         p.city AS provider_city,
         p.area AS provider_area,
         p.rating_avg AS provider_rating_avg,
         p.rating_count AS provider_rating_count,
         p.completed_orders_count AS provider_completed_orders_count,
         p.has_emergency_service AS provider_has_emergency_service,
         p.is_featured AS provider_is_featured,
         p.logo_url AS provider_logo_url,
         p.provider_approval_status AS provider_approval_status,
         p.average_response_minutes AS provider_average_response_minutes,
         p.is_temporarily_paused AS provider_is_temporarily_paused
       FROM service_offerings o
       JOIN service_provider_profiles p ON p.id = o.provider_id
       LEFT JOIN service_categories mc ON mc.id = o.main_category_id
       LEFT JOIN service_categories sc ON sc.id = o.subcategory_id
       WHERE o.provider_id = $1
       ORDER BY o.updated_at DESC, o.id DESC`,
      [provider.id]
    );
    const requestsCountsR = await client.query(
      `SELECT status, COUNT(*)::int AS count
       FROM service_requests
       WHERE provider_id = $1
       GROUP BY status`,
      [provider.id]
    );
    const promotionsR = await client.query(
      `SELECT *
       FROM service_promotions
       WHERE provider_id = $1
       ORDER BY created_at DESC`,
      [provider.id]
    );
    const portfolioR = await client.query(
      `SELECT *
       FROM service_portfolio_items
       WHERE provider_id = $1
       ORDER BY is_pinned DESC, sort_order ASC, id DESC`,
      [provider.id]
    );

    const offerings = offeringsR.rows.map(mapOffering);
    const offeringIds = offerings.map((x) => x.id);
    const pricingMap = await fetchPricingMap(client, offeringIds);
    const mediaMap = await fetchMediaMap(client, offeringIds);

    const requestCounts = {};
    for (const row of requestsCountsR.rows) {
      requestCounts[row.status] = Number(row.count || 0);
    }

    return {
      provider,
      areas: areasR.rows.map((row) => ({
        city: row.city,
        area: row.area || null,
        note: row.note || null,
      })),
      availabilityRules: availabilityR.rows.map((row) => ({
        dayOfWeek: Number(row.day_of_week),
        startTime: row.start_time,
        endTime: row.end_time,
        isActive: row.is_active === true,
      })),
      offerings: offerings.map((offering) => ({
        ...offering,
        pricingOptions: pricingMap.get(offering.id) || [],
        media: mediaMap.get(offering.id) || [],
      })),
      requestCounts,
      promotions: promotionsR.rows.map((row) => mapPromotion(row)),
      portfolio: portfolioR.rows.map((row) => ({
        id: Number(row.id),
        providerId: Number(row.provider_id),
        offeringId: row.offering_id == null ? null : Number(row.offering_id),
        title: row.title || null,
        description: row.description || null,
        mediaUrl: row.media_url,
        mediaKind: row.media_kind || 'image',
        beforeMediaUrl: row.before_media_url || null,
        afterMediaUrl: row.after_media_url || null,
        sortOrder: Number(row.sort_order || 0),
        isPinned: row.is_pinned === true,
      })),
    };
  } finally {
    client.release();
  }
}

export async function findEmployeeProfileForProvider({
  providerId,
  employeeUserId,
}) {
  const r = await q(
    `SELECT *
     FROM service_provider_employee_profile
     WHERE provider_id = $1
       AND employee_user_id = $2
       AND is_active = TRUE
       AND archived_at IS NULL
     LIMIT 1`,
    [Number(providerId), Number(employeeUserId)]
  );
  return r.rows[0] || null;
}

export async function findAnyEmployeeProfileForProvider({
  providerId,
  employeeUserId,
}) {
  const r = await q(
    `SELECT *
     FROM service_provider_employee_profile
     WHERE provider_id = $1
       AND employee_user_id = $2
     LIMIT 1`,
    [Number(providerId), Number(employeeUserId)]
  );
  return r.rows[0] || null;
}

export async function listProviderEmployees({
  providerId,
  search = '',
  limit = 120,
}) {
  const safeLimit = clampLimit(limit, 120);
  const params = [Number(providerId)];
  let searchClause = '';
  const normalizedSearch = String(search || '').trim();
  if (normalizedSearch) {
    params.push(`%${normalizedSearch}%`);
    searchClause =
      "AND (u.full_name ILIKE $2 OR COALESCE(ep.display_name, '') ILIKE $2 OR COALESCE(ep.contact_email, '') ILIKE $2 OR regexp_replace(u.phone, '[^0-9]', '', 'g') ILIKE $2)";
  }
  params.push(safeLimit);
  const limitIndex = params.length;

  const r = await q(
    `SELECT
       u.id,
       u.full_name,
       u.phone,
       u.role,
       u.image_url,
       ep.id AS employee_profile_id,
       ep.role_tag,
       ep.display_name,
       ep.contact_email,
       ep.permissions_json,
       ep.is_active,
       ep.archived_at,
       ep.notes,
       ep.invited_by_user_id,
       ep.updated_by_user_id,
       ep.created_at,
       ep.updated_at
     FROM service_provider_employee_profile ep
     JOIN app_user u ON u.id = ep.employee_user_id
     WHERE ep.provider_id = $1
       ${searchClause}
     ORDER BY ep.updated_at DESC, ep.id DESC
     LIMIT $${limitIndex}`,
    params
  );
  return r.rows;
}

export async function listActiveProviderNotificationRecipients({
  providerId,
  requiredPermissions = [],
} = {}) {
  const permissions = Array.isArray(requiredPermissions)
    ? requiredPermissions
        .map((value) => String(value || '').trim().toLowerCase())
        .filter(Boolean)
    : [];

  const r = await q(
    `SELECT
       u.id AS user_id,
       ep.permissions_json,
       ep.provider_id,
       ep.is_active,
       ep.archived_at,
       u.is_account_disabled,
       p.user_id AS owner_user_id
     FROM service_provider_employee_profile ep
     JOIN app_user u ON u.id = ep.employee_user_id
     JOIN service_provider_profiles p ON p.id = ep.provider_id
     WHERE ep.provider_id = $1
       AND ep.is_active = TRUE
       AND ep.archived_at IS NULL
       AND COALESCE(u.is_account_disabled, FALSE) = FALSE
       AND p.is_active = TRUE
       AND u.id <> p.user_id
     ORDER BY ep.updated_at DESC, ep.id DESC`,
    [Number(providerId)]
  );

  return r.rows
    .map((row) => ({
      userId: Number(row.user_id),
      providerId: Number(row.provider_id),
      permissions: Array.isArray(row.permissions_json)
        ? row.permissions_json
        : [],
    }))
    .filter((row) => {
      if (!Number.isInteger(row.userId) || row.userId <= 0) return false;
      if (!permissions.length) return true;
      return permissions.some((permission) =>
        hasPermission(row.permissions, permission)
      );
    });
}

export async function upsertProviderEmployeeProfile({
  providerId,
  employeeUserId,
  roleTag,
  displayName,
  contactEmail,
  permissions,
  isActive,
  archivedAt,
  notes,
  invitedByUserId,
  updatedByUserId,
}) {
  const r = await q(
    `INSERT INTO service_provider_employee_profile
      (
        provider_id,
        employee_user_id,
        role_tag,
        display_name,
        contact_email,
        permissions_json,
        is_active,
        archived_at,
        notes,
        invited_by_user_id,
        updated_by_user_id,
        created_at,
        updated_at
      )
     VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9,$10,$11,NOW(),NOW())
     ON CONFLICT (provider_id, employee_user_id)
     DO UPDATE SET
       role_tag = EXCLUDED.role_tag,
       display_name = EXCLUDED.display_name,
       contact_email = EXCLUDED.contact_email,
       permissions_json = EXCLUDED.permissions_json,
       is_active = EXCLUDED.is_active,
       archived_at = EXCLUDED.archived_at,
       notes = EXCLUDED.notes,
       invited_by_user_id = COALESCE(EXCLUDED.invited_by_user_id, service_provider_employee_profile.invited_by_user_id),
       updated_by_user_id = EXCLUDED.updated_by_user_id,
       updated_at = NOW()
     RETURNING *`,
    [
      Number(providerId),
      Number(employeeUserId),
      String(roleTag || 'staff').slice(0, 80),
      displayName ? String(displayName).slice(0, 180) : null,
      contactEmail ? String(contactEmail).slice(0, 320) : null,
      JSON.stringify(Array.isArray(permissions) ? permissions : []),
      isActive !== false,
      archivedAt || null,
      notes ? String(notes).slice(0, 3000) : null,
      invitedByUserId == null ? null : Number(invitedByUserId),
      updatedByUserId == null ? null : Number(updatedByUserId),
    ]
  );
  return r.rows[0] || null;
}

export async function listProviderEmployeeActivityLogs({
  providerId,
  employeeUserId = null,
  limit = 120,
}) {
  const safeLimit = clampLimit(limit, 120);
  const params = [Number(providerId)];
  const clauses = ["al.workspace_kind = 'service_provider'", "al.workspace_id = $1"];
  if (employeeUserId != null) {
    params.push(Number(employeeUserId));
    clauses.push(`al.employee_user_id = $${params.length}`);
  }
  params.push(safeLimit);
  const limitIndex = params.length;

  const r = await q(
    `SELECT
       al.*,
       u.full_name AS employee_full_name,
       u.phone AS employee_phone,
       actor.full_name AS actor_full_name
     FROM workspace_employee_activity_log al
     JOIN app_user u ON u.id = al.employee_user_id
     LEFT JOIN app_user actor ON actor.id = al.actor_user_id
     WHERE ${clauses.join(" AND ")}
     ORDER BY al.created_at DESC, al.id DESC
     LIMIT $${limitIndex}`,
    params
  );
  return r.rows;
}

export async function insertProviderEmployeeActivityLog({
  workspaceKind = 'service_provider',
  workspaceId,
  employeeProfileId = null,
  employeeUserId,
  actorUserId = null,
  actorRole = '',
  actionKey,
  reason = null,
  oldValue = {},
  newValue = {},
  note = null,
}) {
  const r = await q(
    `INSERT INTO workspace_employee_activity_log
      (
        workspace_kind,
        workspace_id,
        employee_profile_id,
        employee_user_id,
        actor_user_id,
        actor_role,
        action_key,
        reason,
        old_value,
        new_value,
        note,
        created_at
      )
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10::jsonb,$11,NOW())
     RETURNING *`,
    [
      String(workspaceKind || 'service_provider').slice(0, 24),
      Number(workspaceId),
      employeeProfileId == null ? null : Number(employeeProfileId),
      Number(employeeUserId),
      actorUserId == null ? null : Number(actorUserId),
      String(actorRole || '').slice(0, 40),
      String(actionKey || '').slice(0, 120),
      reason ? String(reason).slice(0, 3000) : null,
      JSON.stringify(oldValue || {}),
      JSON.stringify(newValue || {}),
      note ? String(note).slice(0, 3000) : null,
    ]
  );
  return r.rows[0] || null;
}

export async function saveProvider(userId, providerId) {
  await q(
    `INSERT INTO service_saved_providers (user_id, provider_id)
     VALUES ($1,$2)
     ON CONFLICT (user_id, provider_id) DO NOTHING`,
    [Number(userId), Number(providerId)]
  );
  return true;
}

export async function unsaveProvider(userId, providerId) {
  await q(
    `DELETE FROM service_saved_providers
     WHERE user_id = $1
       AND provider_id = $2`,
    [Number(userId), Number(providerId)]
  );
  return true;
}

export async function saveOffering(userId, offeringId) {
  await q(
    `INSERT INTO service_saved_offerings (user_id, offering_id)
     VALUES ($1,$2)
     ON CONFLICT (user_id, offering_id) DO NOTHING`,
    [Number(userId), Number(offeringId)]
  );
  return true;
}

export async function unsaveOffering(userId, offeringId) {
  await q(
    `DELETE FROM service_saved_offerings
     WHERE user_id = $1
       AND offering_id = $2`,
    [Number(userId), Number(offeringId)]
  );
  return true;
}

export async function listSavedProviders(userId, { limit = 40, offset = 0 } = {}) {
  const r = await q(
    `SELECT
       p.*,
       c.name AS main_category_name,
       u.id AS owner_id,
       u.full_name AS owner_full_name,
       u.image_url AS owner_image_url
     FROM service_saved_providers sp
     JOIN service_provider_profiles p ON p.id = sp.provider_id
     LEFT JOIN service_categories c ON c.id = p.main_category_id
     LEFT JOIN app_user u ON u.id = p.user_id
     WHERE sp.user_id = $1
     ORDER BY sp.created_at DESC
     LIMIT $2 OFFSET $3`,
    [
      Number(userId),
      Math.max(1, Math.min(100, Number(limit) || 40)),
      Math.max(0, Number(offset) || 0),
    ]
  );
  return r.rows.map(mapProvider);
}

export async function listSavedOfferings(userId, { limit = 40, offset = 0 } = {}) {
  const client = await pool.connect();
  try {
    const r = await client.query(
      `SELECT
         o.*,
         mc.name AS main_category_name,
         sc.name AS subcategory_name,
         p.business_name AS provider_business_name,
         p.city AS provider_city,
         p.area AS provider_area,
         p.rating_avg AS provider_rating_avg,
         p.rating_count AS provider_rating_count,
         p.completed_orders_count AS provider_completed_orders_count,
         p.has_emergency_service AS provider_has_emergency_service,
         p.is_featured AS provider_is_featured,
         p.logo_url AS provider_logo_url,
         p.provider_approval_status AS provider_approval_status,
         p.average_response_minutes AS provider_average_response_minutes,
         p.is_temporarily_paused AS provider_is_temporarily_paused
       FROM service_saved_offerings ss
       JOIN service_offerings o ON o.id = ss.offering_id
       JOIN service_provider_profiles p ON p.id = o.provider_id
       LEFT JOIN service_categories mc ON mc.id = o.main_category_id
       LEFT JOIN service_categories sc ON sc.id = o.subcategory_id
       WHERE ss.user_id = $1
       ORDER BY ss.created_at DESC
       LIMIT $2 OFFSET $3`,
      [
        Number(userId),
        Math.max(1, Math.min(100, Number(limit) || 40)),
        Math.max(0, Number(offset) || 0),
      ]
    );
    const offerings = r.rows.map(mapOffering);
    const ids = offerings.map((x) => x.id);
    const pricingMap = await fetchPricingMap(client, ids);
    const mediaMap = await fetchMediaMap(client, ids);
    return offerings.map((offering) => ({
      ...offering,
      pricingOptions: pricingMap.get(offering.id) || [],
      media: mediaMap.get(offering.id) || [],
    }));
  } finally {
    client.release();
  }
}

export async function recordRecentView({ userId, providerId = null, offeringId = null }) {
  await q(
    `INSERT INTO service_recent_views (user_id, provider_id, offering_id, viewed_at)
     VALUES ($1,$2,$3,NOW())`,
    [
      Number(userId),
      providerId == null ? null : Number(providerId),
      offeringId == null ? null : Number(offeringId),
    ]
  );
  return true;
}

export async function listRecentViews(userId, { limit = 40 } = {}) {
  const r = await q(
    `SELECT *
     FROM service_recent_views
     WHERE user_id = $1
     ORDER BY viewed_at DESC, id DESC
     LIMIT $2`,
    [Number(userId), Math.max(1, Math.min(120, Number(limit) || 40))]
  );
  return r.rows.map((row) => ({
    id: Number(row.id),
    userId: Number(row.user_id),
    providerId: row.provider_id == null ? null : Number(row.provider_id),
    offeringId: row.offering_id == null ? null : Number(row.offering_id),
    viewedAt: row.viewed_at || null,
  }));
}

const ACTIVE_PROVIDER_SUBSCRIPTION_REQUEST_STATUSES = [
  'pending_offer',
  'offer_sent',
  'offer_accepted',
  'payment_pending_confirmation',
  'payment_confirmed',
];

async function getSubscriptionRequestByIdWithCategory(client, requestId) {
  const rid = toInt(requestId);
  if (!rid) return null;
  const r = await client.query(
    `SELECT
       sr.*,
       c.name AS main_category_name
     FROM service_provider_subscription_requests sr
     LEFT JOIN service_categories c ON c.id = sr.main_category_id
     WHERE sr.id = $1
     LIMIT 1`,
    [rid]
  );
  return r.rows[0] || null;
}

async function getSubscriptionRequestByPhoneWithCategory(client, phone) {
  const p = String(phone || '').trim();
  if (!p) return null;
  const r = await client.query(
    `SELECT
       sr.*,
       c.name AS main_category_name
     FROM service_provider_subscription_requests sr
     LEFT JOIN service_categories c ON c.id = sr.main_category_id
     WHERE sr.phone = $1
     ORDER BY sr.created_at DESC, sr.id DESC
     LIMIT 1`,
    [p]
  );
  return r.rows[0] || null;
}

async function getPendingSubscriptionOffer(client, requestId, offerId = null) {
  const rid = toInt(requestId);
  if (!rid) return null;
  if (offerId != null) {
    const oid = toInt(offerId);
    if (!oid) return null;
    const found = await client.query(
      `SELECT *
       FROM service_provider_subscription_offers
       WHERE id = $1
         AND request_id = $2
         AND status = 'pending_provider'
       LIMIT 1`,
      [oid, rid]
    );
    return found.rows[0] || null;
  }
  const r = await client.query(
    `SELECT *
     FROM service_provider_subscription_offers
     WHERE request_id = $1
       AND status = 'pending_provider'
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    [rid]
  );
  return r.rows[0] || null;
}

async function getLatestSubscriptionOffer(client, requestId) {
  const rid = toInt(requestId);
  if (!rid) return null;
  const r = await client.query(
    `SELECT *
     FROM service_provider_subscription_offers
     WHERE request_id = $1
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    [rid]
  );
  return r.rows[0] || null;
}

async function appendSubscriptionStatusHistory(
  client,
  {
    requestId,
    fromStatus = null,
    toStatus,
    changedByUserId = null,
    changedByActor = 'system',
    note = null,
    metadata = {},
  }
) {
  const rid = toInt(requestId);
  if (!rid || !toStatus) return;
  await client.query(
    `INSERT INTO service_provider_subscription_status_history (
       request_id,
       from_status,
       to_status,
       changed_by_user_id,
       changed_by_actor,
       note,
       metadata_json,
       created_at
     )
     VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,NOW())`,
    [
      rid,
      fromStatus || null,
      toStatus,
      changedByUserId == null ? null : Number(changedByUserId),
      changedByActor || 'system',
      note || null,
      JSON.stringify(asObj(metadata)),
    ]
  );
}

export async function createProviderSubscriptionRequest({
  dto,
  assets = {},
  pinHash,
  requestCode,
}) {
  const phone = String(dto.phone || '').trim();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const existingActive = await client.query(
      `SELECT
         sr.*,
         c.name AS main_category_name
       FROM service_provider_subscription_requests sr
       LEFT JOIN service_categories c ON c.id = sr.main_category_id
       WHERE sr.phone = $1
         AND sr.status = ANY($2::text[])
       ORDER BY sr.created_at DESC, sr.id DESC
       LIMIT 1
       FOR UPDATE OF sr`,
      [phone, ACTIVE_PROVIDER_SUBSCRIPTION_REQUEST_STATUSES]
    );
    const current = existingActive.rows[0] || null;
    if (current && current.status !== 'pending_offer') {
      const activeOffer = await getLatestSubscriptionOffer(client, current.id);
      await client.query('COMMIT');
      return {
        conflict: true,
        request: mapProviderSubscriptionRequest(current, {
          offer: mapProviderSubscriptionOffer(activeOffer),
        }),
      };
    }

    const payloadValues = [
      dto.fullName,
      dto.businessName,
      phone,
      pinHash,
      assets.logoUrl || null,
      assets.coverImageUrl || null,
      dto.mainCategoryId || null,
      dto.city,
      dto.area || null,
      dto.addressLine || null,
      dto.bio || null,
      dto.whatsappPhone || null,
      dto.servesAtHome === true,
      dto.servesAtShop === true,
      dto.servesRemote === true,
      dto.hasEmergencyService === true,
      dto.bookingPolicy || 'approval_required',
      dto.pricingMode || 'mixed',
      dto.yearsExperience == null ? null : Number(dto.yearsExperience),
      dto.hasTeam === true,
      dto.teamSize == null ? null : Number(dto.teamSize),
      dto.acceptsCash !== false,
      dto.acceptsElectronic === true,
      dto.averageResponseMinutes == null ? null : Number(dto.averageResponseMinutes),
      dto.available247 === true,
      dto.providerGender || null,
      JSON.stringify(Array.isArray(dto.languages) ? dto.languages : []),
      JSON.stringify(Array.isArray(dto.areas) ? dto.areas : []),
      JSON.stringify(Array.isArray(dto.availabilityRules) ? dto.availabilityRules : []),
    ];

    let requestRow = null;
    if (current) {
      const update = await client.query(
        `UPDATE service_provider_subscription_requests
         SET
           full_name = $2,
           business_name = $3,
           phone = $4,
           pin_hash = $5,
           logo_url = $6,
           cover_image_url = $7,
           main_category_id = $8,
           city = $9,
           area = $10,
           address_line = $11,
           bio = $12,
           whatsapp_phone = $13,
           serves_at_home = $14,
           serves_at_shop = $15,
           serves_remote = $16,
           has_emergency_service = $17,
           booking_policy = $18,
           pricing_mode = $19,
           years_experience = $20,
           has_team = $21,
           team_size = $22,
           accepts_cash = $23,
           accepts_electronic = $24,
           average_response_minutes = $25,
           is_available_24_7 = $26,
           provider_gender = $27,
           languages_json = $28::jsonb,
           areas_json = $29::jsonb,
           availability_rules_json = $30::jsonb,
           status = 'pending_offer',
           status_note = NULL,
           selected_offer_id = NULL,
           offered_amount = NULL,
           offered_currency = NULL,
           offered_title = NULL,
           offered_description = NULL,
           offered_valid_until = NULL,
           offer_sent_at = NULL,
           offer_accepted_at = NULL,
           offer_rejected_at = NULL,
           reviewed_by_user_id = NULL,
           reviewed_at = NULL,
           updated_at = NOW()
         WHERE id = $1
         RETURNING id`,
        [Number(current.id), ...payloadValues]
      );
      requestRow = await getSubscriptionRequestByIdWithCategory(
        client,
        Number(update.rows[0].id)
      );
      await appendSubscriptionStatusHistory(client, {
        requestId: requestRow.id,
        fromStatus: current.status,
        toStatus: 'pending_offer',
        changedByActor: 'provider',
        note: 'resubmitted',
      });
    } else {
      const insert = await client.query(
        `INSERT INTO service_provider_subscription_requests (
           request_code,
           full_name,
           business_name,
           phone,
           pin_hash,
           logo_url,
           cover_image_url,
           main_category_id,
           city,
           area,
           address_line,
           bio,
           whatsapp_phone,
           serves_at_home,
           serves_at_shop,
           serves_remote,
           has_emergency_service,
           booking_policy,
           pricing_mode,
           years_experience,
           has_team,
           team_size,
           accepts_cash,
           accepts_electronic,
           average_response_minutes,
           is_available_24_7,
           provider_gender,
           languages_json,
           areas_json,
           availability_rules_json,
           status,
           created_at,
           updated_at
         )
         VALUES (
           $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,
           $21,$22,$23,$24,$25,$26,$27,$28::jsonb,$29::jsonb,$30::jsonb,'pending_offer',NOW(),NOW()
         )
         RETURNING id`,
        [requestCode, ...payloadValues]
      );
      requestRow = await getSubscriptionRequestByIdWithCategory(
        client,
        Number(insert.rows[0].id)
      );
      await appendSubscriptionStatusHistory(client, {
        requestId: requestRow.id,
        fromStatus: null,
        toStatus: 'pending_offer',
        changedByActor: 'provider',
        note: 'created',
      });
    }

    await client.query('COMMIT');
    return {
      conflict: false,
      request: mapProviderSubscriptionRequest(requestRow),
    };
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function getLatestProviderSubscriptionRequestByPhone(phone) {
  const client = await pool.connect();
  try {
    const row = await getSubscriptionRequestByPhoneWithCategory(client, phone);
    if (!row) return null;
    const offer = await getLatestSubscriptionOffer(client, row.id);
    return mapProviderSubscriptionRequest(row, {
      offer: mapProviderSubscriptionOffer(offer),
    });
  } finally {
    client.release();
  }
}

export async function getProviderSubscriptionRequestAuthByPhone(phone) {
  const p = String(phone || '').trim();
  if (!p) return null;
  const r = await q(
    `SELECT *
     FROM service_provider_subscription_requests
     WHERE phone = $1
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    [p]
  );
  return r.rows[0] || null;
}

export async function getProviderSubscriptionRequestById(requestId) {
  const client = await pool.connect();
  try {
    const row = await getSubscriptionRequestByIdWithCategory(client, requestId);
    if (!row) return null;
    const offer = await getLatestSubscriptionOffer(client, row.id);
    return mapProviderSubscriptionRequest(row, {
      offer: mapProviderSubscriptionOffer(offer),
    });
  } finally {
    client.release();
  }
}

export async function getProviderSubscriptionRequestForProvisioning(requestId) {
  const rid = toInt(requestId);
  if (!rid) return null;
  const r = await q(
    `SELECT *
     FROM service_provider_subscription_requests
     WHERE id = $1
     LIMIT 1`,
    [rid]
  );
  return r.rows[0] || null;
}

export async function updateProviderSubscriptionRequestPinHash(requestId, pinHash) {
  const rid = toInt(requestId);
  const normalizedPinHash = String(pinHash || "").trim();
  if (!rid || !normalizedPinHash) return null;
  const result = await q(
    `UPDATE service_provider_subscription_requests
     SET pin_hash = $2,
         updated_at = NOW()
     WHERE id = $1
     RETURNING id, pin_hash`,
    [rid, normalizedPinHash]
  );
  return result.rows[0] || null;
}

export async function listProviderSubscriptionRequestsForAdmin({
  status = null,
  limit = 60,
  offset = 0,
  search = null,
}) {
  const filters = [];
  const values = [];
  if (status) {
    values.push(String(status).trim().toLowerCase());
    filters.push(`sr.status = $${values.length}`);
  }
  if (search && String(search).trim()) {
    values.push(`%${String(search).trim()}%`);
    const idx = values.length;
    filters.push(
      `(sr.full_name ILIKE $${idx} OR sr.business_name ILIKE $${idx} OR sr.phone ILIKE $${idx} OR sr.request_code ILIKE $${idx})`
    );
  }
  values.push(Math.max(1, Math.min(200, Number(limit) || 60)));
  const limitPlaceholder = `$${values.length}`;
  values.push(Math.max(0, Number(offset) || 0));
  const offsetPlaceholder = `$${values.length}`;
  const whereSql = filters.length ? `WHERE ${filters.join(' AND ')}` : '';

  const r = await q(
    `SELECT
       sr.*,
       c.name AS main_category_name
     FROM service_provider_subscription_requests sr
     LEFT JOIN service_categories c ON c.id = sr.main_category_id
     ${whereSql}
     ORDER BY sr.created_at DESC, sr.id DESC
     LIMIT ${limitPlaceholder}
     OFFSET ${offsetPlaceholder}`,
    values
  );

  const client = await pool.connect();
  try {
    const out = [];
    for (const row of r.rows) {
      const offer = await getLatestSubscriptionOffer(client, row.id);
      out.push(
        mapProviderSubscriptionRequest(row, {
          offer: mapProviderSubscriptionOffer(offer),
        })
      );
    }
    return out;
  } finally {
    client.release();
  }
}

export async function adminSendProviderSubscriptionOffer({
  requestId,
  adminUserId,
  dto,
}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT
         sr.*,
         c.name AS main_category_name
       FROM service_provider_subscription_requests sr
       LEFT JOIN service_categories c ON c.id = sr.main_category_id
       WHERE sr.id = $1
       LIMIT 1
       FOR UPDATE OF sr`,
      [Number(requestId)]
    );
    const row = current.rows[0] || null;
    if (!row) {
      await client.query('ROLLBACK');
      return null;
    }
    if (['account_created', 'cancelled', 'rejected'].includes(row.status)) {
      await client.query('ROLLBACK');
      return { error: 'SERVICE_PROVIDER_SUBSCRIPTION_REQUEST_CLOSED' };
    }

    await client.query(
      `UPDATE service_provider_subscription_offers
       SET status = 'superseded', updated_at = NOW()
       WHERE request_id = $1
         AND status = 'pending_provider'`,
      [Number(row.id)]
    );

    const offerInsert = await client.query(
      `INSERT INTO service_provider_subscription_offers (
         request_id,
         offered_by_user_id,
         amount,
         currency,
         title,
         description,
         valid_until,
         status,
         created_at,
         updated_at
       )
       VALUES ($1,$2,$3,$4,$5,$6,$7,'pending_provider',NOW(),NOW())
       RETURNING *`,
      [
        Number(row.id),
        Number(adminUserId),
        Number(dto.amount),
        dto.currency || 'IQD',
        dto.title || null,
        dto.description || null,
        toIsoOrNull(dto.validUntil),
      ]
    );
    const offer = offerInsert.rows[0];

    await client.query(
      `UPDATE service_provider_subscription_requests
       SET
         status = 'offer_sent',
         status_note = $2,
         selected_offer_id = NULL,
         offered_amount = $3,
         offered_currency = $4,
         offered_title = $5,
         offered_description = $6,
         offered_valid_until = $7,
         offer_sent_at = NOW(),
         reviewed_by_user_id = $8,
         reviewed_at = NOW(),
         updated_at = NOW()
       WHERE id = $1`,
      [
        Number(row.id),
        dto.note || null,
        Number(dto.amount),
        dto.currency || 'IQD',
        dto.title || null,
        dto.description || null,
        toIsoOrNull(dto.validUntil),
        Number(adminUserId),
      ]
    );
    await appendSubscriptionStatusHistory(client, {
      requestId: row.id,
      fromStatus: row.status,
      toStatus: 'offer_sent',
      changedByUserId: adminUserId,
      changedByActor: 'admin',
      note: dto.note || null,
      metadata: {
        offerId: Number(offer.id),
        amount: Number(offer.amount),
        currency: offer.currency || 'IQD',
      },
    });

    const refreshed = await getSubscriptionRequestByIdWithCategory(client, row.id);
    await client.query('COMMIT');
    return mapProviderSubscriptionRequest(refreshed, {
      offer: mapProviderSubscriptionOffer(offer),
    });
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function providerRespondToSubscriptionOffer({
  requestId,
  phone,
  action,
  note = null,
  offerId = null,
}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const requestResult = await client.query(
      `SELECT
         sr.*,
         c.name AS main_category_name
       FROM service_provider_subscription_requests sr
       LEFT JOIN service_categories c ON c.id = sr.main_category_id
       WHERE sr.id = $1
         AND sr.phone = $2
       LIMIT 1
       FOR UPDATE OF sr`,
      [Number(requestId), String(phone || '').trim()]
    );
    const requestRow = requestResult.rows[0] || null;
    if (!requestRow) {
      await client.query('ROLLBACK');
      return null;
    }

    const pendingOffer = await getPendingSubscriptionOffer(
      client,
      requestRow.id,
      offerId
    );
    if (!pendingOffer) {
      await client.query('ROLLBACK');
      return { error: 'SERVICE_PROVIDER_SUBSCRIPTION_NO_PENDING_OFFER' };
    }

    const normalizedAction = String(action || '').trim().toLowerCase();
    const nextStatus =
      normalizedAction === 'accept' ? 'offer_accepted' : 'offer_rejected';
    const offerStatus = normalizedAction === 'accept' ? 'accepted' : 'rejected';
    const offerTimeField =
      normalizedAction === 'accept' ? 'offer_accepted_at' : 'offer_rejected_at';

    const offerUpdate = await client.query(
      `UPDATE service_provider_subscription_offers
       SET
         status = $2,
         provider_response_note = $3,
         provider_responded_at = NOW(),
         updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [Number(pendingOffer.id), offerStatus, note || null]
    );
    const updatedOffer = offerUpdate.rows[0];

    await client.query(
      `UPDATE service_provider_subscription_requests
       SET
         status = $2,
         status_note = $3,
         selected_offer_id = $4,
         ${offerTimeField} = NOW(),
         updated_at = NOW()
       WHERE id = $1`,
      [
        Number(requestRow.id),
        nextStatus,
        note || null,
        normalizedAction === 'accept' ? Number(updatedOffer.id) : null,
      ]
    );
    await appendSubscriptionStatusHistory(client, {
      requestId: requestRow.id,
      fromStatus: requestRow.status,
      toStatus: nextStatus,
      changedByActor: 'provider',
      note: note || null,
      metadata: {
        offerId: Number(updatedOffer.id),
        action: normalizedAction,
      },
    });
    const refreshed = await getSubscriptionRequestByIdWithCategory(
      client,
      requestRow.id
    );
    await client.query('COMMIT');
    return mapProviderSubscriptionRequest(refreshed, {
      offer: mapProviderSubscriptionOffer(updatedOffer),
    });
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function adminRejectProviderSubscriptionRequest({
  requestId,
  adminUserId,
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT
         sr.*,
         c.name AS main_category_name
       FROM service_provider_subscription_requests sr
       LEFT JOIN service_categories c ON c.id = sr.main_category_id
       WHERE sr.id = $1
       LIMIT 1
       FOR UPDATE OF sr`,
      [Number(requestId)]
    );
    const row = current.rows[0] || null;
    if (!row) {
      await client.query('ROLLBACK');
      return null;
    }
    if (row.status === 'account_created') {
      await client.query('ROLLBACK');
      return { error: 'SERVICE_PROVIDER_SUBSCRIPTION_ALREADY_COMPLETED' };
    }
    await client.query(
      `UPDATE service_provider_subscription_offers
       SET status = 'cancelled', updated_at = NOW()
       WHERE request_id = $1
         AND status = 'pending_provider'`,
      [Number(row.id)]
    );
    await client.query(
      `UPDATE service_provider_subscription_requests
       SET
         status = 'rejected',
         status_note = $2,
         reviewed_by_user_id = $3,
         reviewed_at = NOW(),
         updated_at = NOW()
       WHERE id = $1`,
      [Number(row.id), note || null, Number(adminUserId)]
    );
    await appendSubscriptionStatusHistory(client, {
      requestId: row.id,
      fromStatus: row.status,
      toStatus: 'rejected',
      changedByUserId: adminUserId,
      changedByActor: 'admin',
      note,
    });
    const refreshed = await getSubscriptionRequestByIdWithCategory(client, row.id);
    const offer = await getLatestSubscriptionOffer(client, row.id);
    await client.query('COMMIT');
    return mapProviderSubscriptionRequest(refreshed, {
      offer: mapProviderSubscriptionOffer(offer),
    });
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function markProviderSubscriptionAccountCreated({
  requestId,
  adminUserId,
  accountCreatedUserId,
  note = null,
}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT
         sr.*,
         c.name AS main_category_name
       FROM service_provider_subscription_requests sr
       LEFT JOIN service_categories c ON c.id = sr.main_category_id
       WHERE sr.id = $1
       LIMIT 1
       FOR UPDATE OF sr`,
      [Number(requestId)]
    );
    const row = current.rows[0] || null;
    if (!row) {
      await client.query('ROLLBACK');
      return null;
    }
    if (row.account_created_user_id) {
      const offer = await getLatestSubscriptionOffer(client, row.id);
      await client.query('COMMIT');
      return mapProviderSubscriptionRequest(row, {
        offer: mapProviderSubscriptionOffer(offer),
      });
    }

    await client.query(
      `UPDATE service_provider_subscription_requests
       SET
         status = 'account_created',
         status_note = $2,
         payment_confirmed_by_user_id = $3,
         payment_confirmed_at = NOW(),
         account_created_user_id = $4,
         account_created_at = NOW(),
         reviewed_by_user_id = $3,
         reviewed_at = NOW(),
         updated_at = NOW()
       WHERE id = $1`,
      [
        Number(row.id),
        note || null,
        Number(adminUserId),
        Number(accountCreatedUserId),
      ]
    );
    await appendSubscriptionStatusHistory(client, {
      requestId: row.id,
      fromStatus: row.status,
      toStatus: 'payment_confirmed',
      changedByUserId: adminUserId,
      changedByActor: 'admin',
      note: 'cash payment confirmed',
      metadata: {
        accountCreatedUserId: Number(accountCreatedUserId),
      },
    });
    await appendSubscriptionStatusHistory(client, {
      requestId: row.id,
      fromStatus: 'payment_confirmed',
      toStatus: 'account_created',
      changedByUserId: adminUserId,
      changedByActor: 'admin',
      note,
      metadata: {
        accountCreatedUserId: Number(accountCreatedUserId),
      },
    });
    const refreshed = await getSubscriptionRequestByIdWithCategory(client, row.id);
    const offer = await getLatestSubscriptionOffer(client, row.id);
    await client.query('COMMIT');
    return mapProviderSubscriptionRequest(refreshed, {
      offer: mapProviderSubscriptionOffer(offer),
    });
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function listPendingProvidersForAdmin({ status = 'pending', limit = 40, offset = 0 }) {
  const r = await q(
    `SELECT
       p.*,
       c.name AS main_category_name,
       u.id AS owner_id,
       u.full_name AS owner_full_name,
       u.image_url AS owner_image_url
     FROM service_provider_profiles p
     LEFT JOIN service_categories c ON c.id = p.main_category_id
     LEFT JOIN app_user u ON u.id = p.user_id
     WHERE p.provider_approval_status = $1
     ORDER BY p.created_at DESC
     LIMIT $2 OFFSET $3`,
    [
      status,
      Math.max(1, Math.min(100, Number(limit) || 40)),
      Math.max(0, Number(offset) || 0),
    ]
  );
  return r.rows.map(mapProvider);
}

export async function adminUpdateProviderStatus({
  providerId,
  status,
  note = null,
  adminUserId,
}) {
  const r = await q(
    `UPDATE service_provider_profiles
     SET
       provider_approval_status = $2::varchar,
       approval_note = $3,
       approved_by_user_id = $4,
       approved_at = CASE WHEN $2::text = 'approved' THEN NOW() ELSE approved_at END,
       updated_at = NOW()
     WHERE id = $1
     RETURNING id`,
    [Number(providerId), status, note || null, Number(adminUserId)]
  );
  if (!r.rows[0]) return null;
  const client = await pool.connect();
  try {
    return await getProviderById(client, providerId);
  } finally {
    client.release();
  }
}

export async function listOfferingsForAdmin({ status = 'pending', limit = 40, offset = 0 }) {
  const client = await pool.connect();
  try {
    const normalizedStatus = String(status || 'pending').trim().toLowerCase();
    const statuses =
      normalizedStatus === 'pending' || normalizedStatus === 'pending_review'
        ? ['pending', 'changes_requested']
        : [normalizedStatus];
    const r = await client.query(
      `SELECT
         o.*,
         mc.name AS main_category_name,
         sc.name AS subcategory_name,
         p.business_name AS provider_business_name,
         p.city AS provider_city,
         p.area AS provider_area,
         p.rating_avg AS provider_rating_avg,
         p.rating_count AS provider_rating_count,
         p.completed_orders_count AS provider_completed_orders_count,
         p.has_emergency_service AS provider_has_emergency_service,
         p.is_featured AS provider_is_featured,
         p.logo_url AS provider_logo_url,
         p.provider_approval_status AS provider_approval_status,
         p.average_response_minutes AS provider_average_response_minutes,
         p.is_temporarily_paused AS provider_is_temporarily_paused
       FROM service_offerings o
       JOIN service_provider_profiles p ON p.id = o.provider_id
       LEFT JOIN service_categories mc ON mc.id = o.main_category_id
       LEFT JOIN service_categories sc ON sc.id = o.subcategory_id
       WHERE o.moderation_status = ANY($1::text[])
       ORDER BY o.created_at DESC
       LIMIT $2 OFFSET $3`,
      [
        statuses,
        Math.max(1, Math.min(100, Number(limit) || 40)),
        Math.max(0, Number(offset) || 0),
      ]
    );
    const offerings = r.rows.map(mapOffering);
    const ids = offerings.map((x) => x.id);
    const pricingMap = await fetchPricingMap(client, ids);
    const mediaMap = await fetchMediaMap(client, ids);
    return offerings.map((offering) => ({
      ...offering,
      pricingOptions: pricingMap.get(offering.id) || [],
      media: mediaMap.get(offering.id) || [],
    }));
  } finally {
    client.release();
  }
}

export async function adminUpdateOfferingStatus({
  offeringId,
  status,
  note = null,
  adminUserId,
}) {
  const r = await q(
    `UPDATE service_offerings
     SET
       moderation_status = $2,
       moderation_note = $3,
       moderated_by_user_id = $4,
       moderated_at = NOW(),
       updated_at = NOW()
     WHERE id = $1
     RETURNING provider_id`,
    [Number(offeringId), status, note || null, Number(adminUserId)]
  );
  if (!r.rows[0]) return null;
  const client = await pool.connect();
  try {
    return await getOfferingForProvider(client, Number(r.rows[0].provider_id), offeringId);
  } finally {
    client.release();
  }
}

export async function listCategorySuggestionsForAdmin({
  status = 'pending',
  limit = 60,
  offset = 0,
}) {
  const r = await q(
    `SELECT
       s.*,
       u.full_name AS suggested_by_name,
       c.name AS parent_category_name,
       m.name AS merge_target_category_name
     FROM service_category_suggestions s
     LEFT JOIN app_user u ON u.id = s.suggested_by_user_id
     LEFT JOIN service_categories c ON c.id = s.parent_category_id
     LEFT JOIN service_categories m ON m.id = s.merge_target_category_id
     WHERE s.status = $1
     ORDER BY s.created_at DESC
     LIMIT $2 OFFSET $3`,
    [
      status,
      Math.max(1, Math.min(120, Number(limit) || 60)),
      Math.max(0, Number(offset) || 0),
    ]
  );
  return r.rows.map((row) => ({
    id: Number(row.id),
    suggestedByUserId: Number(row.suggested_by_user_id),
    suggestedByName: row.suggested_by_name || null,
    parentCategoryId: row.parent_category_id == null ? null : Number(row.parent_category_id),
    parentCategoryName: row.parent_category_name || null,
    suggestionType: row.suggestion_type,
    name: row.name,
    details: row.details || null,
    status: row.status,
    mergeTargetCategoryId:
      row.merge_target_category_id == null ? null : Number(row.merge_target_category_id),
    mergeTargetCategoryName: row.merge_target_category_name || null,
    reviewedByUserId:
      row.reviewed_by_user_id == null ? null : Number(row.reviewed_by_user_id),
    reviewedAt: row.reviewed_at || null,
    reviewNote: row.review_note || null,
    createdAt: row.created_at || null,
  }));
}

export async function adminReviewCategorySuggestion({
  suggestionId,
  action,
  reviewNote = null,
  mergeTargetCategoryId = null,
  adminUserId,
}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const sR = await client.query(
      `SELECT *
       FROM service_category_suggestions
       WHERE id = $1
       LIMIT 1`,
      [Number(suggestionId)]
    );
    const suggestion = sR.rows[0] || null;
    if (!suggestion) {
      await client.query('ROLLBACK');
      return null;
    }

    if (action === 'approved') {
      const level = suggestion.suggestion_type === 'main' ? 1 : 2;
      const parentId = level === 1 ? null : suggestion.parent_category_id;
      const sortR = await client.query(
        `SELECT COALESCE(MAX(sort_order), 0) + 1 AS next_sort
         FROM service_categories
         WHERE parent_id IS NOT DISTINCT FROM $1`,
        [parentId]
      );
      const nextSort = Number(sortR.rows[0]?.next_sort || 1);
      await client.query(
        `INSERT INTO service_categories (
           parent_id, level, name, sort_order, is_active, is_public, created_by_user_id, created_at, updated_at
         )
         VALUES ($1,$2,$3,$4,TRUE,TRUE,$5,NOW(),NOW())
         ON CONFLICT (parent_id_resolved, normalized_name) DO NOTHING`,
        [parentId, level, suggestion.name, nextSort, Number(adminUserId)]
      );
      await client.query(
        `UPDATE service_category_suggestions
         SET
           status = 'approved',
           reviewed_by_user_id = $2,
           reviewed_at = NOW(),
           review_note = $3,
           updated_at = NOW()
         WHERE id = $1`,
        [Number(suggestionId), Number(adminUserId), reviewNote || null]
      );
    } else if (action === 'merged') {
      await client.query(
        `UPDATE service_category_suggestions
         SET
           status = 'merged',
           merge_target_category_id = $2,
           reviewed_by_user_id = $3,
           reviewed_at = NOW(),
           review_note = $4,
           updated_at = NOW()
         WHERE id = $1`,
        [
          Number(suggestionId),
          mergeTargetCategoryId == null ? null : Number(mergeTargetCategoryId),
          Number(adminUserId),
          reviewNote || null,
        ]
      );
    } else {
      await client.query(
        `UPDATE service_category_suggestions
         SET
           status = 'rejected',
           reviewed_by_user_id = $2,
           reviewed_at = NOW(),
           review_note = $3,
           updated_at = NOW()
         WHERE id = $1`,
        [Number(suggestionId), Number(adminUserId), reviewNote || null]
      );
    }

    await client.query('COMMIT');
    const out = await listCategorySuggestionsForAdmin({
      status: action === 'approved' ? 'approved' : action,
      limit: 1,
      offset: 0,
    });
    return out[0] || null;
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // ignore
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function listServiceRequestsForAdmin({ status = null, limit = 60, offset = 0 }) {
  const params = [];
  const filters = ['1=1'];
  if (status) {
    params.push(status);
    filters.push(`sr.status = $${params.length}`);
  }
  params.push(Math.max(1, Math.min(120, Number(limit) || 60)));
  params.push(Math.max(0, Number(offset) || 0));
  const r = await q(
    `SELECT
       sr.*,
       so.name AS offering_name,
       sp.business_name AS provider_business_name,
       au.full_name AS customer_full_name
     FROM service_requests sr
     JOIN service_offerings so ON so.id = sr.offering_id
     JOIN service_provider_profiles sp ON sp.id = sr.provider_id
     JOIN app_user au ON au.id = sr.customer_user_id
     WHERE ${filters.join(' AND ')}
     ORDER BY sr.created_at DESC, sr.id DESC
     LIMIT $${params.length - 1}
     OFFSET $${params.length}`,
    params
  );
  return r.rows.map(mapRequest);
}

export async function listServiceReportsForAdmin({ status = 'pending', limit = 60, offset = 0 }) {
  const r = await q(
    `SELECT *
     FROM service_reports
     WHERE status = $1
     ORDER BY created_at DESC
     LIMIT $2 OFFSET $3`,
    [
      status,
      Math.max(1, Math.min(120, Number(limit) || 60)),
      Math.max(0, Number(offset) || 0),
    ]
  );
  return r.rows.map((row) => ({
    id: Number(row.id),
    reporterUserId: Number(row.reporter_user_id),
    targetType: row.target_type,
    targetId: Number(row.target_id),
    reason: row.reason || null,
    details: row.details || null,
    status: row.status,
    reviewedByUserId:
      row.reviewed_by_user_id == null ? null : Number(row.reviewed_by_user_id),
    reviewedAt: row.reviewed_at || null,
    reviewNote: row.review_note || null,
    createdAt: row.created_at || null,
  }));
}

export async function adminReviewReport({ reportId, status, reviewNote, adminUserId }) {
  const r = await q(
    `UPDATE service_reports
     SET
       status = $2,
       reviewed_by_user_id = $3,
       reviewed_at = NOW(),
       review_note = $4,
       updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [Number(reportId), status, Number(adminUserId), reviewNote || null]
  );
  const row = r.rows[0] || null;
  if (!row) return null;
  return {
    id: Number(row.id),
    reporterUserId: Number(row.reporter_user_id),
    targetType: row.target_type,
    targetId: Number(row.target_id),
    reason: row.reason || null,
    details: row.details || null,
    status: row.status,
    reviewedByUserId:
      row.reviewed_by_user_id == null ? null : Number(row.reviewed_by_user_id),
    reviewedAt: row.reviewed_at || null,
    reviewNote: row.review_note || null,
    createdAt: row.created_at || null,
  };
}

export async function getServicesAdminDashboardStats() {
  const [providersR, offeringsR, requestsR, reviewsR, topCategoriesR] = await Promise.all([
    q(
      `SELECT provider_approval_status AS key, COUNT(*)::int AS count
       FROM service_provider_profiles
       GROUP BY provider_approval_status`
    ),
    q(
      `SELECT moderation_status AS key, COUNT(*)::int AS count
       FROM service_offerings
       GROUP BY moderation_status`
    ),
    q(
      `SELECT status AS key, COUNT(*)::int AS count
       FROM service_requests
       GROUP BY status`
    ),
    q(
      `SELECT
         COUNT(*)::int AS total_reviews,
         COALESCE(AVG(rating), 0)::numeric(4,2) AS avg_rating
       FROM service_reviews`
    ),
    q(
      `SELECT
         c.id,
         c.name,
         COUNT(*)::int AS offerings_count
       FROM service_offerings o
       LEFT JOIN service_categories c ON c.id = o.main_category_id
       GROUP BY c.id, c.name
       ORDER BY offerings_count DESC NULLS LAST
       LIMIT 12`
    ),
  ]);
  return {
    providersByStatus: providersR.rows.reduce((acc, row) => {
      acc[row.key] = Number(row.count || 0);
      return acc;
    }, {}),
    offeringsByStatus: offeringsR.rows.reduce((acc, row) => {
      acc[row.key] = Number(row.count || 0);
      return acc;
    }, {}),
    requestsByStatus: requestsR.rows.reduce((acc, row) => {
      acc[row.key] = Number(row.count || 0);
      return acc;
    }, {}),
    reviews: {
      total: Number(reviewsR.rows[0]?.total_reviews || 0),
      averageRating: Number(reviewsR.rows[0]?.avg_rating || 0),
    },
    topCategories: topCategoriesR.rows.map((row) => ({
      id: row.id == null ? null : Number(row.id),
      name: row.name || 'غير مصنّف',
      offeringsCount: Number(row.offerings_count || 0),
    })),
  };
}

export async function listServiceModuleSettings() {
  const r = await q(`SELECT * FROM service_module_settings ORDER BY id ASC`);
  return r.rows.map((row) => ({
    id: Number(row.id),
    key: row.key,
    value: asObj(row.value_json),
    updatedByUserId:
      row.updated_by_user_id == null ? null : Number(row.updated_by_user_id),
    updatedAt: row.updated_at || null,
  }));
}

export async function upsertServiceModuleSetting({ key, value, adminUserId }) {
  const r = await q(
    `INSERT INTO service_module_settings (key, value_json, updated_by_user_id, updated_at)
     VALUES ($1,$2::jsonb,$3,NOW())
     ON CONFLICT (key)
     DO UPDATE SET
       value_json = EXCLUDED.value_json,
       updated_by_user_id = EXCLUDED.updated_by_user_id,
       updated_at = NOW()
     RETURNING *`,
    [key, JSON.stringify(asObj(value)), Number(adminUserId)]
  );
  const row = r.rows[0] || null;
  if (!row) return null;
  return {
    id: Number(row.id),
    key: row.key,
    value: asObj(row.value_json),
    updatedByUserId:
      row.updated_by_user_id == null ? null : Number(row.updated_by_user_id),
    updatedAt: row.updated_at || null,
  };
}
