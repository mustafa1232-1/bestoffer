import "dotenv/config";
import os from "os";

import { app } from "./app.js";
import { ensureSchema, getDbFailoverState, pool, q } from "./config/db.js";
import { env, validateRuntimeEnv } from "./config/env.js";
import { closeRedisClient } from "./config/redis.js";
import { runSqlMigrations } from "./config/sqlMigrations.js";
import {
  startSocialCallLifecycleWorker,
  startSocialScheduledMessageWorker,
  startSocialStreamReconciliationWorker,
  stopSocialStreamReconciliationWorker,
} from "./modules/feed/feed.service.js";
import { logStreamConfigStartup } from "./modules/feed/feed.stream-config.js";
import { startOrderAttentionReminderWorker, stopOrderAttentionReminderWorker } from "./modules/notifications/order-attention.worker.js";
import { startInventoryReservationWorker, stopInventoryReservationWorker } from "./modules/orders/inventory-reservation.worker.js";
import {
  startDeliveryAssignmentRecoveryWorker,
  stopDeliveryAssignmentRecoveryWorker,
} from "./modules/orders/delivery-assignment.worker.js";
import { startPaidUpgradeMaintenanceWorker, stopPaidUpgradeMaintenanceWorker } from "./modules/paid-upgrades/paid-upgrades.service.js";
import { startTaxiLifecycleWorker } from "./modules/taxi/taxi.service.js";
import { seedOpsRunbooks } from "./ops/runbooksLoader.js";
import { initDatadogTracing } from "./ops/tools/datadogTool.js";
import { hashPin } from "./shared/utils/hash.js";
import {
  initLiveEventBus,
  shutdownLiveEventBus,
} from "./shared/realtime/live-events.js";
import {
  startRealtimeOutboxPump,
  stopRealtimeOutboxPump,
} from "./shared/realtime/realtime-outbox.js";

/**
 * Purpose:
 * ملف الإقلاع الرئيسي للسيرفر. يرتب التحقق من البيئة، تشغيل migrations
 * الخفيفة، تجهيز الحسابات الإدارية الأساسية، ثم تشغيل العمال الدوريين
 * وبدء الاستماع على المنفذ الفعلي.
 *
 * Used by:
 * - `npm start`
 * - `npm run dev`
 * - فحوص الصحة والتشغيل التي تعتمد على boot sequence المكتمل
 *
 * Depends on:
 * - `app.js` لتركيب Express
 * - `config/env.js` و`config/db.js`
 * - services الخاصة بالـ workers (taxi/feed/notifications/paid-upgrades)
 *
 * Critical notes:
 * - أي فشل هنا يمنع التطبيق كله من العمل.
 * - مشاكل boot غالباً تكون من env ناقص، DB غير متاحة، أو migration/schema
 *   guard لا يستطيع التنفيذ.
 *
 * Maintenance notes:
 * - عند فشل التشغيل افحص أولاً `validateRuntimeEnv()` ثم `runSqlMigrations()`
 *   ثم `ensureSchema()` ثم صلاحية الاتصال بـ PostgreSQL وRedis/R2.
 * - لا تنقل منطق business ثقيل إلى هذا الملف؛ المطلوب هنا orchestration فقط.
 */
const port = env.port;
const host = env.host;
let activeServer = null;
let shutdownInProgress = false;
let sentryModulePromise = null;

async function captureProcessErrorToSentry(error) {
  if (!String(process.env.SENTRY_DSN || "").trim()) return;
  try {
    if (!sentryModulePromise) {
      sentryModulePromise = import("@sentry/node")
        .then((mod) => mod.default || mod)
        .catch(() => null);
    }
    const sentry = await sentryModulePromise;
    if (!sentry || typeof sentry.captureException !== "function") return;
    sentry.captureException(error);
  } catch (_) {
    // best effort
  }
}

/**
 * يبني username آمن ومحدد الطول لاستخدامه أثناء seeding للحسابات الإدارية.
 *
 * نحتاجه لأن جدول `app_user.username` يفرض قيود طول/صيغة، وبعض البيئات
 * القديمة كانت تتعطل عند إدخال قيمة seed غير صالحة أو متصادمة.
 */
function buildSeedUsername(prefix, phone) {
  const digits = String(phone || "").replace(/\D+/g, "");
  const suffix = digits.slice(-6) || "000000";
  let username = `${prefix}.${suffix}`
    .toLowerCase()
    .replace(/[^a-z0-9._]+/g, ".")
    .replace(/[._]{2,}/g, ".")
    .replace(/^[._]+|[._]+$/g, "");

  if (username.length < 4) {
    username = `user.${suffix}`.slice(0, 24);
  }

  if (username.length > 24) {
    username = username.slice(0, 24).replace(/[._]+$/g, "");
  }

  if (!/^[a-z0-9]/.test(username)) {
    username = `u${username}`.slice(0, 24);
  }
  if (!/[a-z0-9]$/.test(username)) {
    username = `${username}0`.slice(0, 24);
  }
  if (username.length < 4) {
    username = username.padEnd(4, "0");
  }

  return username;
}

/**
 * يضمن وجود super admin واحد صالح بعد اكتمال boot.
 *
 * Side effects:
 * - يكتب إلى `app_user`
 * - يصفر أي علامة `is_super_admin` سابقة قبل إعادة تثبيت الحساب المعتمد
 *
 * Maintenance notes:
 * - إذا فشل seed هنا فافحص `SUPER_ADMIN_*` في env، ثم قيود `app_user`
 *   خصوصاً `phone` و`username` و`is_super_admin`.
 */
async function ensureSuperAdminAccount() {
  const superPhone = String(env.superAdminPhone || "").trim();
  const superPin = String(env.superAdminPin || "").trim();
  const superName = String(env.superAdminName || "Super Admin").trim();
  const superUsername = buildSeedUsername("maslaki.admin", superPhone);

  if (!/^\d{8,20}$/.test(superPhone) || !/^\d{4,8}$/.test(superPin)) {
    console.warn("[seed] skipped super admin seeding due to invalid phone/pin.");
    return;
  }

  const pinHash = await hashPin(superPin);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    // Advisory lock prevents race condition when multiple instances boot simultaneously
    await client.query(`SELECT pg_advisory_xact_lock(9876543210)`);
    await client.query(
      `UPDATE app_user
       SET is_super_admin = FALSE
       WHERE is_super_admin = TRUE`
    );

    await client.query(
      `INSERT INTO app_user
        (
          full_name,
          username,
          phone,
          pin_hash,
          block,
          building_number,
          apartment,
          role,
          is_super_admin,
          analytics_consent_granted,
          analytics_consent_version,
          analytics_consent_granted_at
        )
       VALUES ($1,$2,$3,$4,'A','1','1','admin',TRUE,TRUE,'system_seed_v1',NOW())
       ON CONFLICT (phone)
       DO UPDATE SET
         full_name = EXCLUDED.full_name,
         username = COALESCE(NULLIF(app_user.username, ''), EXCLUDED.username),
         pin_hash = EXCLUDED.pin_hash,
         role = 'admin',
         is_super_admin = TRUE,
         analytics_consent_granted = TRUE,
         analytics_consent_version = 'system_seed_v1',
         analytics_consent_granted_at = COALESCE(
           app_user.analytics_consent_granted_at,
           NOW()
         )`,
      [superName, superUsername, superPhone, pinHash]
    );

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }

  const seeded = await q(
    `SELECT id
     FROM app_user
     WHERE phone = $1
     LIMIT 1`,
    [superPhone]
  );

  const superAdminUserId = seeded.rows[0]?.id;
  if (superAdminUserId) {
    console.log(
      `[seed] Super admin ready -> phone: ${superPhone}, userId: ${superAdminUserId}`
    );
  }
}

/**
 * يزرع حساب admin تطويري محلي غير مستخدم في production.
 *
 * الهدف منه تسريع QA المحلي عندما لا تكون قاعدة البيانات مهيأة مسبقاً.
 * أي تغيير في هذا المسار يجب أن يبقى محصوراً ببيئات غير production.
 */
async function ensureDevAdmin() {
  if (process.env.NODE_ENV === "production") return;
  if (process.env.DEV_SEED_ADMIN === "false") return;

  const adminPhone = String(
    process.env.DEV_ADMIN_PHONE || "07701234567"
  ).trim();
  const adminPin = String(process.env.DEV_ADMIN_PIN || "1234").trim();
  const adminName = String(process.env.DEV_ADMIN_NAME || "Admin").trim();
  const adminUsername = buildSeedUsername("dev.admin", adminPhone);

  if (!/^\d{4,20}$/.test(adminPhone) || !/^\d{4,8}$/.test(adminPin)) {
    console.warn("[seed] skipped DEV admin seeding due to invalid phone/pin.");
    return;
  }

  const pinHash = await hashPin(adminPin);

  await q(
    `INSERT INTO app_user
      (full_name, username, phone, pin_hash, block, building_number, apartment, role)
     VALUES ($1,$2,$3,$4,'A','1','1','admin')
     ON CONFLICT (phone)
     DO UPDATE
       SET full_name = EXCLUDED.full_name,
           username = COALESCE(NULLIF(app_user.username, ''), EXCLUDED.username),
           pin_hash = EXCLUDED.pin_hash,
           role = 'admin'`,
    [adminName, adminUsername, adminPhone, pinHash]
  );

  console.log(`[seed] Dev admin ready -> phone: ${adminPhone}, pin: ${adminPin}`);
}

/**
 * ترتيب الإقلاع الرسمي للتطبيق.
 *
 * Return value:
 * - يعيد كائن `server` بعد بدء الاستماع.
 *
 * Critical notes:
 * - لا يبدأ listen قبل اكتمال env validation وschema guards والworkers.
 * - أي خطأ غير ملتقط هنا يعتبر failure تشغيلي كامل وليس failure جزئي.
 */
async function start() {
  validateRuntimeEnv();
  await initDatadogTracing({ env });
  await runSqlMigrations();
  await ensureSchema();
  await seedOpsRunbooks();
  await ensureSuperAdminAccount();
  await ensureDevAdmin();
  await initLiveEventBus();
  startRealtimeOutboxPump();
  startSocialCallLifecycleWorker();
  startSocialScheduledMessageWorker();
  startSocialStreamReconciliationWorker();
  logStreamConfigStartup();
  startTaxiLifecycleWorker();
  startOrderAttentionReminderWorker();
  startInventoryReservationWorker();
  startDeliveryAssignmentRecoveryWorker();
  startPaidUpgradeMaintenanceWorker();

  const server = app.listen(port, host, () => {
    console.log(`Server running on http://${host}:${port}`);
    const dbTopology = getDbFailoverState();
    console.log(
      `[db] strategy=${dbTopology.strategy} writeTarget=${dbTopology.writeTarget} readTarget=${dbTopology.readTarget}`
    );
    console.log(
      `[runtime] workerSlot=${env.appWorkerSlot || 0} workersTotal=${env.appWorkersTotal || 1} pid=${process.pid}`
    );

    const ifaces = os.networkInterfaces();
    const ipv4 = [];
    for (const entries of Object.values(ifaces)) {
      for (const entry of entries || []) {
        if (entry.family === "IPv4" && !entry.internal) {
          ipv4.push(entry.address);
        }
      }
    }
    if (ipv4.length) {
      console.log(`[net] LAN IPv4: ${ipv4.join(", ")}`);
    }
  });

  server.requestTimeout = env.requestTimeoutMs;
  server.headersTimeout = env.requestTimeoutMs + 1000;
  activeServer = server;
  return server;
}

/**
 * يغلق التطبيق بشكل متدرج ويحاول تحرير server/redis/db قبل الخروج النهائي.
 *
 * Maintenance notes:
 * - عند تعليق عملية الإغلاق راقب `activeServer.close` ثم Redis ثم pool.end`.
 * - وجود force-exit بعد timeout مقصود لمنع العمليات المعلقة من إبقاء الحاوية حية.
 */
async function shutdown(reason, exitCode = 0) {
  if (shutdownInProgress) return;
  shutdownInProgress = true;
  console.warn(`[shutdown] reason=${reason}`);

  const forceExitTimer = setTimeout(() => {
    console.error("[shutdown] force exit after timeout");
    process.exit(exitCode || 1);
  }, 12_000);
  forceExitTimer.unref();

  // Stop background workers first to prevent new DB activity
  stopOrderAttentionReminderWorker();
  stopInventoryReservationWorker();
  await stopDeliveryAssignmentRecoveryWorker();
  stopSocialStreamReconciliationWorker();
  stopPaidUpgradeMaintenanceWorker();

  try {
    if (activeServer) {
      await new Promise((resolve) => activeServer.close(resolve));
    }
  } catch (error) {
    console.error("[shutdown] server close failed:", error);
    exitCode = 1;
  }

  try {
    await stopRealtimeOutboxPump();
  } catch (error) {
    console.error("[shutdown] realtime outbox close failed:", error);
    exitCode = 1;
  }

  try {
    await pool.end();
  } catch (error) {
    console.error("[shutdown] db pool close failed:", error);
    exitCode = 1;
  }

  try {
    await closeRedisClient();
  } catch (error) {
    console.error("[shutdown] redis close failed:", error);
    exitCode = 1;
  }

  try {
    await shutdownLiveEventBus();
  } catch (error) {
    console.error("[shutdown] live event bus close failed:", error);
    exitCode = 1;
  }

  clearTimeout(forceExitTimer);
  process.exit(exitCode);
}

/**
 * يربط إشارات النظام الحرجة بآلية shutdown الموحدة.
 *
 * يشمل SIGTERM/SIGINT والأخطاء غير الملتقطة كي تبقى طريقة الإغلاق واحدة
 * ويمكن تتبعها بسهولة من logs الإنتاج.
 */
function registerProcessHandlers() {
  process.on("SIGINT", () => {
    void shutdown("SIGINT", 0);
  });
  process.on("SIGTERM", () => {
    void shutdown("SIGTERM", 0);
  });
  process.on("unhandledRejection", (reason) => {
    console.error("[process] unhandledRejection:", reason);
    void captureProcessErrorToSentry(reason);
    void shutdown("unhandledRejection", 1);
  });
  process.on("uncaughtException", (error) => {
    console.error("[process] uncaughtException:", error);
    void captureProcessErrorToSentry(error);
    void shutdown("uncaughtException", 1);
  });
}

registerProcessHandlers();

start().catch((err) => {
  console.error("Failed to start server:", err);
  process.exit(1);
});
