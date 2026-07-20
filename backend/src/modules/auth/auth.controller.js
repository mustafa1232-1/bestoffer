import * as service from "./auth.service.js";
import {
  validateAddressCreate,
  validateAddressUpdate,
  validateLogin,
  validateRefreshSession,
  validateRegister,
  validateRegisterWithCard,
  validateUpdateAccount,
} from "./auth.validators.js";
import {
  assertUploadedFileSignature,
  buildUploadedFileUrl,
} from "../../shared/utils/upload.js";
import { extractDeviceContext } from "../../shared/utils/device-fingerprint.js";
import { resolveAccessAuth } from "../../shared/middleware/access-auth.js";

/**
 * Purpose:
 * controllers المصادقة والحساب. تجهز body/validation/device context ثم
 * تمرر التنفيذ إلى `auth.service.js` مع contract HTTP موحد.
 *
 * Used by:
 * - `auth.routes.js`
 *
 * Critical notes:
 * - هذا الملف لا يجب أن يحمل business logic ثقيلة؛ مهمته الأساسية
 *   validation, normalization, response shape.
 */

/**
 * ينشئ body التسجيل، يربط الصورة المرفوعة إن وجدت، ثم ينفذ تسجيل الحساب.
 */
export async function register(req, res, next) {
  try {
    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, req.file) || req.body?.imageUrl,
    };

    const v = validateRegister(body);
    if (!v.ok) return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });

    const out = await service.register(body, extractDeviceContext(req));
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * helper محلي يسمح بقراءة payloads JSON القادمة كسلسلة نصية من multipart
 * دون كسر المسارات القديمة.
 */
function parseJsonMaybe(value) {
  if (value == null) return null;
  if (typeof value === "object") return value;
  if (typeof value !== "string") return null;
  const text = value.trim();
  if (!text) return null;
  try {
    const parsed = JSON.parse(text);
    return typeof parsed === "object" && parsed != null ? parsed : null;
  } catch (_) {
    return null;
  }
}

export async function extractResidenceCard(req, res, next) {
  try {
    if (!req.file || !req.file.buffer || req.file.buffer.length === 0) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: ["cardImageFile"],
      });
    }
    assertUploadedFileSignature(req.file, "residence_card");

    const out = await service.extractResidenceCard({
      imageBuffer: req.file.buffer,
      mimeType: req.file.mimetype || null,
      fileName: req.file.originalname || "card.jpg",
    });

    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * ينفذ تسجيل الحساب مع بطاقة السكن والملفات المرتبطة في طلب multipart واحد.
 */
export async function registerWithCard(req, res, next) {
  try {
    const profileImageFile = Array.isArray(req.files?.imageFile)
      ? req.files.imageFile[0]
      : null;
    const cardImageFile = Array.isArray(req.files?.cardImageFile)
      ? req.files.cardImageFile[0]
      : null;

    const body = {
      ...req.body,
      imageUrl: buildUploadedFileUrl(req, profileImageFile) || req.body?.imageUrl,
      cardImageUrl: buildUploadedFileUrl(req, cardImageFile) || req.body?.cardImageUrl,
      extractedPayload: parseJsonMaybe(req.body?.extractedPayload),
      residenceInfo: parseJsonMaybe(req.body?.residenceInfo),
    };

    if (!body.cardImageUrl) {
      return res.status(400).json({
        message: "VALIDATION_ERROR",
        fields: ["cardImageFile"],
      });
    }

    const v = validateRegisterWithCard(body);
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.registerWithResidenceCard(
      body,
      { cardImageUrl: body.cardImageUrl || null },
      extractDeviceContext(req)
    );
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * يسجل دخول المستخدم ويربط device fingerprint الحالي بالجلسة.
 */
export async function login(req, res, next) {
  try {
    const v = validateLogin(req.body);
    if (!v.ok) return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });

    const out = await service.login(req.body, extractDeviceContext(req));
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function refreshSession(req, res, next) {
  try {
    const v = validateRefreshSession(req.body || {});
    if (!v.ok) {
      return res.status(400).json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.refreshSession(
      v.value.refreshToken,
      extractDeviceContext(req)
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * يحدث بيانات الحساب الأساسية للمستخدم الحالي.
 */
export async function updateAccount(req, res, next) {
  try {
    const v = validateUpdateAccount(req.body || {});
    if (!v.ok) {
      return res
        .status(400)
        .json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.updateAccount(req.userId, req.body || {}, {
      currentSessionId: req.authSessionId || null,
    });
    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * ينهي الجلسة الحالية فقط.
 */
export async function logout(req, res, next) {
  try {
    const auth = await resolveOptionalAuth(req);
    if (!auth) {
      return res.json({ revoked: false });
    }

    const out = await service.logout(auth.userId, auth.sessionId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * ينهي كل الجلسات النشطة للمستخدم.
 */
export async function logoutAll(req, res, next) {
  try {
    const auth = await resolveOptionalAuth(req);
    if (!auth) {
      return res.json({ revokedCount: 0 });
    }

    const out = await service.logoutAll(auth.userId, auth.sessionId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function listSessions(req, res, next) {
  try {
    const out = await service.listSessions(req.userId);
    res.json({ sessions: out, currentSessionId: req.authSessionId || null });
  } catch (e) {
    next(e);
  }
}

/**
 * يعيد عناوين التوصيل الخاصة بالمستخدم الحالي.
 */
export async function listAddresses(req, res, next) {
  try {
    const out = await service.getAddresses(req.userId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

/**
 * ينشئ عنوان توصيل جديداً بعد التحقق من حقول بسماية.
 */
export async function createAddress(req, res, next) {
  try {
    const v = validateAddressCreate(req.body || {});
    if (!v.ok) {
      return res
        .status(400)
        .json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.createAddress(req.userId, req.body || {});
    res.status(201).json(out);
  } catch (e) {
    next(e);
  }
}

export async function updateAddress(req, res, next) {
  try {
    const v = validateAddressUpdate(req.body || {});
    if (!v.ok) {
      return res
        .status(400)
        .json({ message: "VALIDATION_ERROR", fields: v.errors });
    }

    const out = await service.updateAddress(
      req.userId,
      req.params.addressId,
      req.body || {}
    );
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function setDefaultAddress(req, res, next) {
  try {
    const out = await service.setDefaultAddress(req.userId, req.params.addressId);
    res.json(out);
  } catch (e) {
    next(e);
  }
}

export async function deleteAddress(req, res, next) {
  try {
    await service.deleteAddress(req.userId, req.params.addressId);
    res.status(204).send();
  } catch (e) {
    next(e);
  }
}

async function resolveOptionalAuth(req) {
  const authorization = String(req?.headers?.authorization || "");
  const hasBearer = authorization.startsWith("Bearer ");
  const bearerToken = hasBearer ? authorization.slice("Bearer ".length).trim() : "";
  const looksLikeJwt = bearerToken.split(".").length === 3;
  const attempts = looksLikeJwt ? 5 : 1;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const auth = await resolveAccessAuth(req, { strict: false });
      if (auth) {
        return {
          userId: auth.userId,
          sessionId: auth.sessionId || null,
        };
      }
    } catch (_) {
      // Logout routes are idempotent; invalid tokens still resolve as no-op.
    }
    if (attempt < attempts - 1) {
      await new Promise((resolve) =>
        setTimeout(resolve, [100, 250, 500, 1000][attempt] || 1000)
      );
    }
  }
  return null;
}
