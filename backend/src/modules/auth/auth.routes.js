import { Router } from "express";
import * as c from "./auth.controller.js";
import {
  imageUpload,
  registerWithCardUpload,
  residenceCardUpload,
} from "../../shared/utils/upload.js";
import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import { requireSignedRequest } from "../../shared/middleware/request-signing.middleware.js";

/**
 * Purpose:
 * جميع مسارات المصادقة الأساسية للمستخدم النهائي: التسجيل، تسجيل الدخول،
 * الجلسات، تحديث الحساب، وعناوين التوصيل.
 *
 * Critical notes:
 * - هذه المسارات أول نقطة دخول لكل الأدوار تقريباً.
 * - ترتبط مباشرةً بالواجهة في شاشات auth/account/address management.
 *
 * Maintenance notes:
 * - أعطال auth الشائعة تُفحص هنا بالترتيب:
 *   upload/validation -> controller -> auth.service -> auth.repo -> JWT/session.
 */
export const authRouter = Router();
const requireSensitiveWriteSignature = requireSignedRequest();

// التسجيل الأساسي للمستخدم مع صورة اختيارية.
authRouter.post("/register", imageUpload.single("imageFile"), c.register);
// OCR بطاقة السكن يستخدم قبل التسجيل المساعد بالبطاقة.
authRouter.post(
  "/ocr/extract-residence-card",
  residenceCardUpload.single("cardImageFile"),
  c.extractResidenceCard
);
authRouter.post(
  "/register-with-card",
  registerWithCardUpload.fields([
    { name: "imageFile", maxCount: 1 },
    { name: "cardImageFile", maxCount: 1 },
  ]),
  c.registerWithCard
);
authRouter.post("/login", c.login);
authRouter.post("/refresh", c.refreshSession);
authRouter.post("/logout", c.logout);
authRouter.post("/logout-all", c.logoutAll);
authRouter.get("/sessions", requireAuth, c.listSessions);
// إدارة بيانات الحساب والعناوين تستخدم لاحقاً في checkout والطلبات.
authRouter.patch(
  "/account",
  requireAuth,
  requireSensitiveWriteSignature,
  c.updateAccount
);
authRouter.get("/account/addresses", requireAuth, c.listAddresses);
authRouter.post("/account/addresses", requireAuth, c.createAddress);
authRouter.put("/account/addresses/:addressId", requireAuth, c.updateAddress);
authRouter.patch(
  "/account/addresses/:addressId/default",
  requireAuth,
  c.setDefaultAddress
);
authRouter.delete("/account/addresses/:addressId", requireAuth, c.deleteAddress);
