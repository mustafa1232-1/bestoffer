/* eslint-disable no-console */
import "dotenv/config";

import { pool, q } from "../config/db.js";
import { allocateRegistrationUsername } from "../modules/auth/auth.service.js";
import { hashPin } from "../shared/utils/hash.js";

const REVIEW_PHONE = "07721234567";
const REVIEW_PIN = "1234";
const REVIEW_NAME = "apple review account";
const REVIEW_CATEGORY = "Apple Review Services";
const REVIEW_SUBCATEGORY = "Quick Booking";
const REVIEW_SERVICE = "Quick Apple Review Booking";
const REVIEW_IMAGE_URL =
  "https://images.unsplash.com/photo-1581092160562-40aa08e78837?auto=format&fit=crop&w=1400&q=80";

function normalizePhone(value) {
  return String(value || "").replace(/[^\d]/g, "");
}

async function upsertReviewUser(client) {
  const phone = normalizePhone(REVIEW_PHONE);
  const pinHash = await hashPin(REVIEW_PIN);
  const existing = await client.query(
    `SELECT id, username FROM app_user WHERE phone = $1 LIMIT 1`,
    [phone],
  );
  const username =
    existing.rows[0]?.username ||
    (await allocateRegistrationUsername({
      fullName: REVIEW_NAME,
      phone,
    }));

  const row = await client.query(
    `INSERT INTO app_user (
       full_name,
       username,
       phone,
       pin_hash,
       block,
       building_number,
       apartment,
       role,
       image_url,
       analytics_consent_granted,
       analytics_consent_version,
       analytics_consent_granted_at,
       created_at,
       updated_at
     )
     VALUES ($1,$2,$3,$4,'A1','A101','101','service_provider',$5,TRUE,'apple_review_seed_v1',NOW(),NOW(),NOW())
     ON CONFLICT (phone)
     DO UPDATE
       SET full_name = EXCLUDED.full_name,
           username = COALESCE(NULLIF(app_user.username, ''), EXCLUDED.username),
           pin_hash = EXCLUDED.pin_hash,
           role = 'service_provider',
           image_url = COALESCE(app_user.image_url, EXCLUDED.image_url),
           analytics_consent_granted = TRUE,
           analytics_consent_version = 'apple_review_seed_v1',
           analytics_consent_granted_at = COALESCE(app_user.analytics_consent_granted_at, NOW()),
           updated_at = NOW()
     RETURNING id, phone, role`,
    [REVIEW_NAME, username, phone, pinHash, REVIEW_IMAGE_URL],
  );
  return row.rows[0];
}

async function upsertCategory(client, { name, parentId = null, level = 1 }) {
  const sort = await client.query(
    `SELECT COALESCE(MAX(sort_order), 0) + 1 AS next_sort
     FROM service_categories
     WHERE parent_id IS NOT DISTINCT FROM $1`,
    [parentId],
  );
  const row = await client.query(
    `INSERT INTO service_categories (
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
     VALUES ($1,$2,$3,$4,TRUE,TRUE,NULL,NOW(),NOW())
     ON CONFLICT (parent_id_resolved, normalized_name)
     DO UPDATE
       SET is_active = TRUE,
           is_public = TRUE,
           updated_at = NOW()
     RETURNING id, name`,
    [parentId, level, name, Number(sort.rows[0]?.next_sort || 1)],
  );
  return row.rows[0];
}

async function upsertProvider(client, { userId, categoryId }) {
  const existing = await client.query(
    `SELECT id FROM service_provider_profiles WHERE user_id = $1 LIMIT 1`,
    [userId],
  );
  if (existing.rows[0]) {
    const row = await client.query(
      `UPDATE service_provider_profiles
       SET business_name = $2,
           logo_url = COALESCE(logo_url, $3),
           cover_image_url = COALESCE(cover_image_url, $3),
           main_category_id = $4,
           bio = $5,
           phone = $6,
           whatsapp_phone = $6,
           city = 'Baghdad',
           area = 'Basmaya',
           address_line = 'Basmaya review service address',
           serves_at_home = TRUE,
           serves_at_shop = FALSE,
           serves_remote = FALSE,
           has_emergency_service = FALSE,
           booking_policy = 'instant',
           pricing_mode = 'fixed',
           accepts_cash = TRUE,
           accepts_electronic = FALSE,
           average_response_minutes = 5,
           provider_approval_status = 'approved',
           approval_note = 'Apple review account. Registration is free; Maslaki records a 10% commission on completed bookings. Cash is handled through the office and electronic payment is not enabled yet.',
           approved_at = COALESCE(approved_at, NOW()),
           updated_at = NOW()
       WHERE id = $1
       RETURNING id, user_id, business_name, provider_approval_status`,
      [
        Number(existing.rows[0].id),
        REVIEW_NAME,
        REVIEW_IMAGE_URL,
        categoryId,
        "A ready-to-book review service provider account for Apple App Review.",
        REVIEW_PHONE,
      ],
    );
    return row.rows[0];
  }

  const row = await client.query(
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
       $1,$2,$3,$3,$4,$5,$6,$6,'Baghdad','Basmaya','Basmaya review service address',
       TRUE,FALSE,FALSE,FALSE,'instant','fixed',5,FALSE,NULL,TRUE,FALSE,5,FALSE,
       'not_applicable','["ar","en"]'::jsonb,$7,'approved',
       'Apple review account. Registration is free; Maslaki records a 10% commission on completed bookings. Cash is handled through the office and electronic payment is not enabled yet.',
       NULL,NOW(),NOW(),NOW()
     )
     RETURNING id, user_id, business_name, provider_approval_status`,
    [
      userId,
      REVIEW_NAME,
      REVIEW_IMAGE_URL,
      categoryId,
      "A ready-to-book review service provider account for Apple App Review.",
      REVIEW_PHONE,
      `${REVIEW_NAME} ${REVIEW_SERVICE} quick booking`,
    ],
  );
  return row.rows[0];
}

async function upsertOffering(
  client,
  { providerId, categoryId, subcategoryId },
) {
  const existing = await client.query(
    `SELECT id FROM service_offerings
     WHERE provider_id = $1 AND lower(name) = lower($2)
     LIMIT 1`,
    [providerId, REVIEW_SERVICE],
  );
  const commonValues = [
    categoryId,
    subcategoryId,
    REVIEW_SERVICE,
    "A simple fixed-price service created for Apple App Review. It can be booked quickly without electronic payment.",
    "home",
    true,
    false,
    30,
    true,
    5000,
    false,
    false,
    1,
    "Quick visit, basic check, and clear service confirmation.",
    "Materials or spare parts are not included.",
    "Payment is cash only. Electronic payment will be enabled later.",
    "Apple review seed service",
    true,
    false,
    true,
    false,
    `${REVIEW_SERVICE} apple review service quick booking`,
  ];

  let offeringId;
  if (existing.rows[0]) {
    const row = await client.query(
      `UPDATE service_offerings
       SET main_category_id = $2,
           subcategory_id = $3,
           name = $4,
           description = $5,
           execution_mode = $6,
           requires_schedule = $7,
           requires_provider_approval = $8,
           estimated_duration_minutes = $9,
           has_fixed_price = $10,
           starts_from_price = $11,
           inspection_required = $12,
           custom_quote_only = $13,
           workers_count = $14,
           includes_text = $15,
           excludes_text = $16,
           materials_text = $17,
           notes = $18,
           supports_hourly_booking = $19,
           supports_daily_booking = $20,
           supports_visit_booking = $21,
           supports_full_day_booking = $22,
           search_text = $23,
           moderation_status = 'approved',
           updated_at = NOW()
       WHERE id = $1
       RETURNING id`,
      [Number(existing.rows[0].id), ...commonValues],
    );
    offeringId = Number(row.rows[0].id);
  } else {
    const row = await client.query(
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
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,'approved',NOW(),NOW())
       RETURNING id`,
      [providerId, ...commonValues],
    );
    offeringId = Number(row.rows[0].id);
  }

  await client.query(
    `DELETE FROM service_pricing_options WHERE offering_id = $1`,
    [offeringId],
  );
  await client.query(
    `INSERT INTO service_pricing_options (
       offering_id,
       pricing_model,
       pricing_unit,
       label,
       amount,
       currency,
       inspection_required,
       notes,
       is_default,
       is_active,
       sort_order,
       created_at,
       updated_at
     )
     VALUES ($1,'fixed_package','visit','Quick fixed booking',5000,'IQD',FALSE,'Cash payment only',TRUE,TRUE,0,NOW(),NOW())`,
    [offeringId],
  );

  await client.query(
    `DELETE FROM service_offering_media WHERE offering_id = $1`,
    [offeringId],
  );
  await client.query(
    `INSERT INTO service_offering_media (offering_id, media_url, media_kind, sort_order)
     VALUES ($1,$2,'image',0)`,
    [offeringId, REVIEW_IMAGE_URL],
  );
  return offeringId;
}

async function main() {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const user = await upsertReviewUser(client);
    const category = await upsertCategory(client, {
      name: REVIEW_CATEGORY,
      level: 1,
    });
    const subcategory = await upsertCategory(client, {
      name: REVIEW_SUBCATEGORY,
      parentId: Number(category.id),
      level: 2,
    });
    const provider = await upsertProvider(client, {
      userId: Number(user.id),
      categoryId: Number(category.id),
    });
    const offeringId = await upsertOffering(client, {
      providerId: Number(provider.id),
      categoryId: Number(category.id),
      subcategoryId: Number(subcategory.id),
    });
    await client.query("COMMIT");

    console.log("[apple-review-service-provider] PASS");
    console.log(`phone=${REVIEW_PHONE}`);
    console.log(`pin=${REVIEW_PIN}`);
    console.log(`userId=${user.id}`);
    console.log(`providerId=${provider.id}`);
    console.log(`offeringId=${offeringId}`);
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      // ignore rollback failure
    }
    console.error("[apple-review-service-provider] FAIL", error);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
