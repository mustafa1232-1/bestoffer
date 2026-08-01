import { Router } from "express";

import { requireAuth } from "../../shared/middleware/auth.middleware.js";
import * as staff from "./staff.controller.js";

// خدمة ذاتية لموظف الشركة (المرحلة 7). requireAuth + التحقق من كونه موظفاً في
// الـcontroller.
export const staffRouter = Router();

staffRouter.use(requireAuth);

staffRouter.get("/attendance/status", staff.myStatus);
staffRouter.post("/attendance/check-in", staff.checkIn);
staffRouter.post("/attendance/check-out", staff.checkOut);
staffRouter.get("/attendance/mine", staff.myAttendance);

staffRouter.post("/expenses", staff.submitExpense);
staffRouter.get("/expenses/mine", staff.myExpenses);

staffRouter.get("/payslips/mine", staff.myPayslips);
staffRouter.post("/payslips/:runId/acknowledge", staff.acknowledgePayslip);

staffRouter.post("/reviews/:period/objection", staff.objectToReview);

// "كوبوني": the employee's own referral-coupon earnings (25% of company
// commission on completed orders redeemed through their coupon).
staffRouter.get("/coupon/earnings", staff.myCouponEarnings);
